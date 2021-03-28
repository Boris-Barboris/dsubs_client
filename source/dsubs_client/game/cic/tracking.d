/*
DSubs
Copyright (C) 2017-2021 Baranin Alexander

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU Affero General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU Affero General Public License for more details.

You should have received a copy of the GNU Affero General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/
module dsubs_client.game.cic.tracking;

import std.array: array, appender;
import std.algorithm;
import std.range;

import core.time: seconds;

import dsubs_common.math;
import dsubs_common.api.entities;
import dsubs_common.api.marshalling;

import dsubs_client.game.cic.protocol;
import dsubs_client.game.cic.persistence;
import dsubs_client.game.cic.messages;
import dsubs_client.game.cic.entities;
import dsubs_client.game.cic.state;
import dsubs_client.common;


private struct WaterfallSlice
{
	AntennaeData[] antData;
	usecs_t atTime;
	double worldRot;
	vec2d worldPos;
}

private struct HydrophoneTrackerContext
{
	HydrophoneTracker tracker;
	short counter = TRACKER_GEN_FREQ - 1;			/// increases with each acoustics update
	short lossCounter = TRACKER_LOSS_TIMEOUT - 2;	/// this many times the tracker did not found a signal it was bound to
	double prevWrot;		/// last time the tracker was active this was it's rotation
	usecs_t prevTime;		/// same for time
	double angVel = 0.0;	/// angular velocity of a tracker.
}

private struct Peak
{
	float rot;		/// world-space rotation
	float dist = float.max;
	bool locked;	/// tracker occupies this peak
}

private
{
	/// ray data will be generated after each TRACKER_GEN_FREQ data were received
	enum short TRACKER_GEN_FREQ = 15;
	/// tracker is automatically switched to inactive state after this many update cycles with
	/// no signal found.
	enum short TRACKER_LOSS_TIMEOUT = 20;
	enum float CAPTURE_SEEK_AREA_PERSEC = dgr2rad(4);
	enum float CAPTURE_SEEK_MAX_AREA = dgr2rad(8);
	enum float ANGVEL_FILTER_K = 0.66;
	enum float DETECTION_MARGIN_TO_NOISE = 2.45f;
	/// after how many data slices we redo our noise estimation
	enum int NOISE_ESTIMATION_FREQUENCY = 3;
}


/// We synchronize ray generation for trackers that track the same
/// contact.
struct RayGeneratorSynchronizer
{
	/// map from contactId to tracker count. If there are more than one tracker,
	/// all contact trackers will be synchronized and generate rays simultaniously.
	private int[ContactId] trackerCounts;

	/// get the number of ray generators that are bound to contact.
	int get(ContactId ctcId) const
	{
		return trackerCounts.get(ctcId, 0);
	}

	void increase(ContactId ctcId)
	{
		trackerCounts.update(ctcId, { return 1; }, (ref int current) => current + 1);
	}

	void decrease(ContactId ctcId)
	{
		assert(ctcId in trackerCounts);
		int result = --trackerCounts[ctcId];
		assert(result >= 0);
		if (result == 0)
			trackerCounts.remove(ctcId);
	}

	void clear()
	{
		trackerCounts.clear();
	}
}


final class WaterfallAnalyzer: Persistable
{
	private
	{
		WaterfallSlice m_lastSlice;
		int m_sensorIdx;
		string m_subId;
		const HydrophoneTemplate m_tmpl;
		HydrophoneTrackerContext*[TrackerId] m_trackers;
		RayGeneratorSynchronizer* m_sync;
		Peak[] m_peaks, m_freePeaks;
		// min signal value in the last slice
		int m_min;
		ushort m_detectMargin = ushort.max / 8;
		bool m_noiseEstimated;
		int m_noiseEstimationCounter;
		float m_varianceEstimate;


		@Compressed
		struct OnDiskState
		{
			enum int g_marshIdx = 1;
			HydrophoneTrackerContext[] trackers;
		}
	}

	this(string subId, const HydrophoneTemplate tmpl,
		int sensorIdx, RayGeneratorSynchronizer* sync)
	{
		m_subId = subId;
		m_tmpl = tmpl;
		super("trackers " ~ m_tmpl.name);
		m_saveInterval = seconds(5);
		m_sensorIdx = sensorIdx;
		m_sync = sync;
		m_peaks.reserve(32);
	}

	void recoverFromDisk(CICState mainState)
	{
		OnDiskState* recoveredState = loadFromFile!OnDiskState();
		if (recoveredState)
			loadFromMessage(*recoveredState, mainState);
	}

	override immutable(ubyte)[] buildOnDiskMessage()
	{
		OnDiskState stateStruct;
		stateStruct.trackers = m_trackers.byValue.map!(tc => *tc).array;
		return marshalMessage(cast(immutable) &stateStruct);
	}

	override string getFileName()
	{
		return m_subId ~ "_trackers_" ~ m_sensorIdx.to!string;
	}

	private void loadFromMessage(OnDiskState state, CICState mainState)
	{
		foreach (ref ctx; state.trackers)
		{
			ContactId ctcId = ctx.tracker.id.ctcId;
			// Trackers and main CIC state data are saved with different frequencies.
			// Contact list may become out of sync, hence we need to ignore trackers
			// for phantom contacts.
			if (mainState.contactExists(ctcId))
			{
				m_trackers[ctx.tracker.id] = &ctx;
				m_sync.increase(ctcId);
			}
		}
	}

	/// Record new hydrophone data and analyze it. Move or deactivate trackers.
	void processNewData(HydrophoneData hdata, usecs_t atTime)
	{
		m_lastSlice.antData = hdata.antennaes;
		m_lastSlice.atTime = atTime;
		m_lastSlice.worldRot = hdata.rotation;
		m_lastSlice.worldPos = hdata.position;

		// recalculate min
		m_min = int.max;
		foreach (AntennaeData d; hdata.antennaes)
			m_min = min(m_min, minElement(d.beams));

		if ((!m_noiseEstimated || m_noiseEstimationCounter == 0) && m_min > 0)
		{
			int deltas = 0;
			float deltaSqrSum = 0.0f;
			// estimate noise
			foreach (AntennaeData d; hdata.antennaes)
			{
				for (size_t i = 0; i < d.beams.length - 1; i++)
				{
					deltas++;
					deltaSqrSum += pow(
						d.beams[i + 1].to!float - d.beams[i].to!float, 2);
				}
			}
			m_varianceEstimate = deltaSqrSum / deltas;
			m_detectMargin = ceil(sqrt(m_varianceEstimate) * DETECTION_MARGIN_TO_NOISE).
				lrint.to!ushort;
			m_noiseEstimated = true;
		}
		m_noiseEstimationCounter =
			(m_noiseEstimationCounter + 1) % NOISE_ESTIMATION_FREQUENCY;

		// find all peaks and write them to array
		m_peaks.length = 0;
		m_freePeaks.length = 0;
		int beamCount = hdata.antennaes[0].beams.length.to!int;
		foreach (i, AntennaeData d; hdata.antennaes)
		{
			double andLeftWrot = m_lastSlice.worldRot + m_tmpl.antRots[i] + m_tmpl.fov / 2;
			ushort[] beams = m_lastSlice.antData[i].beams;
			foreach (j, ushort ilevel; beams)
			{
				ushort ilevelPrev = j > 0 ? beams[j - 1] : ushort.max;
				ushort ilevelNext = j < beams.length - 2 ? beams[j + 1] : ushort.max;
				if (ilevel > (m_min + m_detectMargin) &&
					ilevel >= ilevelPrev && ilevel > ilevelNext)
				{
					// we've found the peak
					float beamRot, beamFractIdx;
					// if we're the middle pixel we can try peak interpolation
					if (j > 0 && j < beams.length - 2)
					{
						float centerOfMass = (
							-cast(int)(ilevelPrev - m_min) + (ilevelNext - m_min)) /
							(ilevel + ilevelPrev + ilevelNext - 3 * m_min).to!float;
						beamFractIdx = j + centerOfMass;
					}
					else
						beamFractIdx = j;
					beamRot = clampAngle(andLeftWrot -
							(beamFractIdx + 0.5f) * (m_tmpl.fov / beamCount));
					m_peaks ~= Peak(beamRot);
				}
			}
		}
		//trace("current peaks: ", m_peaks);
		// Update active trackers
		HydrophoneTrackerContext*[] trackers = m_trackers.byValue.
			filter!(t => t.tracker.state == TrackerState.active).array;
		// trackers without lost signals must bind to peaks first
		trackers.sort!"a.lossCounter < b.lossCounter";
		//trace("current tracker contexts: ", trackers.map!(a => *a));
		m_freePeaks = m_peaks;
		foreach (HydrophoneTrackerContext* htc; trackers)
		{
			float sinceLast = (atTime - htc.prevTime) / 1e6f;
			float expectedWrot = htc.prevWrot + htc.angVel * sinceLast;
			assert(!isNaN(expectedWrot));
			htc.counter = (htc.counter + 1) % TRACKER_GEN_FREQ;
			if (m_freePeaks.length > 0)
			{
				// try to find the closest to expectedWrot peak
				foreach (ref Peak p; m_freePeaks)
					p.dist = angleDist(p.rot, expectedWrot).fabs;
				m_freePeaks.sort!"a.dist < b.dist";
				if (m_freePeaks[0].dist <= min(
					CAPTURE_SEEK_AREA_PERSEC * min(sinceLast, TRACKER_LOSS_TIMEOUT),
					CAPTURE_SEEK_MAX_AREA))
				{
					m_freePeaks[0].locked = true;
					htc.lossCounter = 0;
					double newAngVel = angleDist(m_freePeaks[0].rot, htc.prevWrot) / sinceLast;
					htc.angVel = lerp(htc.angVel, newAngVel, ANGVEL_FILTER_K);
					htc.prevTime = atTime;
					htc.tracker.bearing = htc.prevWrot = m_freePeaks[0].rot;
					m_freePeaks = m_freePeaks[1 .. $];
				}
				else
					htc.lossCounter = min(htc.lossCounter + 1, TRACKER_LOSS_TIMEOUT).to!short;
			}
			else
			{
				htc.lossCounter = min(htc.lossCounter + 1, TRACKER_LOSS_TIMEOUT).to!short;
			}
			// too many cycles without a trace, deactivate tracker
			if (htc.lossCounter == TRACKER_LOSS_TIMEOUT)
				htc.tracker.state = TrackerState.inactive;
		}
	}

	/// allocate array of rotations and copy peaks into it
	float[] getPeaks()
	{
		float[] res;
		res.length = m_peaks.length;
		for (int i = 0; i < m_peaks.length; i++)
			res[i] = m_peaks[i].rot;
		return res;
	}

	/// allocate array of rotations and copy all trackers into it
	HydrophoneTracker[] getTrackers()
	{
		HydrophoneTracker[] res;
		res.reserve(m_trackers.length);
		foreach (tc; m_trackers.byValue)
			res ~= tc.tracker;
		return res;
	}

	void mergeTrackers(ContactId source, ContactId dest)
	{
		TrackerId sourceId = TrackerId(m_sensorIdx, source);
		TrackerId destId = TrackerId(m_sensorIdx, dest);
		HydrophoneTrackerContext** sourceCtx = sourceId in m_trackers;
		if (sourceCtx is null)
			return;
		HydrophoneTrackerContext** destCtx = destId in m_trackers;
		if (destCtx is null || (*sourceCtx).tracker.state == TrackerState.active)
		{
			(*sourceCtx).tracker.id.ctcId = dest;
			m_trackers[destId] = *sourceCtx;
			// update tracker counts
			m_sync.decrease(source);
			if (destCtx is null)
				m_sync.increase(dest);
		}
		m_trackers.remove(sourceId);
	}

	bool dropTracker(ContactId cid)
	{
		TrackerId tid = TrackerId(m_sensorIdx, cid);
		bool wasDropped = m_trackers.remove(tid);
		if (wasDropped)
			m_sync.decrease(cid);
		return wasDropped;
	}

	HydrophoneTracker createTracker(TrackerId tid, float bearing)
	{
		assert(tid.sensorIdx == m_sensorIdx);
		HydrophoneTrackerContext* ctx = new HydrophoneTrackerContext(
			HydrophoneTracker(tid, bearing, TrackerState.active));
		ctx.prevWrot = bearing;
		ctx.prevTime = m_lastSlice.atTime;
		m_trackers[tid] = ctx;
		m_sync.increase(tid.ctcId);
		return ctx.tracker;
	}

	/// Force-update tracker bearing, reset it's state to active and give it 2 cycles
	/// to lock on the target. Returns true if the update was made.
	bool updateTracker(ContactId cid, float bearing, out HydrophoneTracker newState)
	{
		TrackerId tid = TrackerId(m_sensorIdx, cid);
		HydrophoneTrackerContext** ctxPtr = tid in m_trackers;
		if (ctxPtr is null)
			return false;
		HydrophoneTrackerContext* ctx = *ctxPtr;
		ctx.angVel = 0.0;
		ctx.prevTime = m_lastSlice.atTime;
		ctx.prevWrot = bearing;
		ctx.lossCounter = TRACKER_LOSS_TIMEOUT - 2;
		ctx.tracker.state = TrackerState.active;
		ctx.tracker.bearing = bearing;
		newState = ctx.tracker;
		return true;
	}

	/// Generate contact data from active trackers wich counters are in the right position
	ContactData[] generateRayData(usecs_t currentTime)
	{
		ContactData[] res;
		if (currentTime != m_lastSlice.atTime)
			return [];
		foreach (tc; m_trackers.byValue)
		{
			ContactId ctcId = tc.tracker.id.ctcId;
			bool mustBeSync = (m_sync.get(ctcId) > 1);
			bool timeToGenerate = mustBeSync ?
				(currentTime / 1000_000 % TRACKER_GEN_FREQ) == 0 :
				tc.counter == 0;
			if (tc.tracker.state == TrackerState.active &&
				timeToGenerate && tc.lossCounter == 0)
			{
				ContactData data = ContactData(-1, tc.tracker.id.ctcId, currentTime,
					DataSource(DataSourceType.Hydrophone, m_sensorIdx), DataType.Ray);
				RayData ray = RayData(m_lastSlice.worldPos, tc.tracker.bearing);
				data.data.ray = ray;
				res ~= data;
			}
		}
		return res;
	}
}