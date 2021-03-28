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
module dsubs_client.game.cic.server;

import std.random;

import core.time: msecs;
import core.thread;

import dsubs_common.api.messages;

import dsubs_client.common;
import dsubs_client.core.utils;
import dsubs_client.game;
import dsubs_client.game.cic.listener;
import dsubs_client.game.cic.messages;
import dsubs_client.game.cic.state;
import dsubs_client.game.cic.tracking;
import dsubs_client.game.connections.backend;

public import dsubs_client.game.connections.cicclient;


/**
CIC stands for combat information center. It is a broadcast and synchronization
server responsible for cooperative gameplay.
*/
final class CICServer
{
	private
	{
		CICListener m_listener;
		CICState m_state;
		BackendConnection m_bcon;
		WaterfallAnalyzer[] m_wfAnalizers;
		RayGeneratorSynchronizer* m_raySyncer;
		bool m_dead;

		Thread m_fuzzerThread;
	}

	@property BackendConnection bcon() { return m_bcon; }

	this(string password, BackendConnection bcon)
	{
		m_listener = new CICListener(this, password);
		m_state = new CICState();
		m_raySyncer = new RayGeneratorSynchronizer();
		m_bcon = bcon;
	}

	void start()
	{
		assert(m_listener);
		m_listener.start();
		Game.window.title = "dsubs (coop port " ~ m_listener.port.to!string ~ ")";
	}

	@property CICListener listener() { return m_listener; }
	@property CICState state() { return m_state; }
	@property bool dead() const { return m_dead; }

	void stop()
	{
		info("ensuring that CIC server down");
		m_listener.stop();
	}

	void handleReconnectStateRes(ReconnectStateRes res)
	{
		enforce(!m_state.recStateInitialized,
			"protocol flow error: unexpected duplicate ReconnectStateRes");
		m_state.handleReconnectStateRes(res);
		const SubmarineTemplate sbmTpl = *Game.entityManager.
			submarineTemplates[res.submarineName];
		foreach (size_t i, const HydrophoneTemplate ht; sbmTpl.hydrophones)
		{
			WaterfallAnalyzer alz = new WaterfallAnalyzer(
				res.subId, ht, i.to!int, m_raySyncer);
			alz.recoverFromDisk(m_state);
			m_wfAnalizers ~= alz;
		}
		m_state.signalStateReady();
		// m_fuzzerThread = new Thread(&fuzzyContactDropper);
		// m_fuzzerThread.start();
	}

	private void fuzzyContactDropper()
	{
		int postfix = 0;
		while(true)
		{
			CICCreateContactFromDataReq req;
			req.ctcIdPrefix = 'F';
			req.initialData.time = 0;
			req.initialData.source.type = DataSourceType.Manual;
			req.initialData.type = DataType.Position;
			req.initialData.data.position =
				PositionData(vec2d(0, 0));
			postfix++;
			handleCICCreateContactFromDataReq(req);
			Thread.sleep(msecs(10));
			ContactId ctcId = ContactId('F', postfix);
			CICDropContactReq dropReq;
			dropReq.ctcId = ctcId;
			handleCICDropContactReq(dropReq);
			Thread.sleep(msecs(10));
		}
	}

	void handleSubKinematicRes(SubKinematicRes res)
	{
		synchronized(m_state.rsMut)
		{
			m_state.handleSubKinematicRes(res);
		}
		m_listener.broadcast(cast(immutable CICSubKinematicRes) res);
	}

	void handleCICThrottleReq(CICThrottleReq req)
	{
		synchronized
		{
			synchronized(m_state.rsMut)
			{
				if (m_dead)
					return;
				m_state.handleThrottleReq(req);
			}
			m_bcon.sendMessage(cast(immutable ThrottleReq) req);
			m_listener.broadcast(cast(immutable) req);
		}
	}

	void handleCICCourseReq(CICCourseReq req)
	{
		synchronized
		{
			synchronized(m_state.rsMut)
			{
				if (m_dead)
					return;
				m_state.handleCourseReq(req);
			}
			m_bcon.sendMessage(cast(immutable CourseReq) req);
			m_listener.broadcast(cast(immutable) req);
		}
	}

	void handleCICListenDirReq(CICListenDirReq req)
	{
		synchronized
		{
			synchronized(m_state.rsMut)
			{
				if (m_dead)
					return;
				m_state.handleListenDirReq(req);
			}
			m_bcon.sendMessage(cast(immutable ListenDirReq) req);
			m_listener.broadcast(cast(immutable) req);
		}
	}

	void handleCICWireDesiredLengthReq(CICWireDesiredLengthReq req)
	{
		synchronized
		{
			synchronized(m_state.rsMut)
			{
				if (m_dead)
					return;
				m_state.handleWireDesiredLengthReq(req);
			}
			m_bcon.sendMessage(cast(immutable WireDesiredLengthReq) req);
			m_listener.broadcast(cast(immutable) req);
		}
	}

	void handleSimFlowEndRes(SimFlowEndRes res)
	{
		synchronized(m_state.ctcMut)
		{
			synchronized(m_state.rsMut)
			{
				// we assubme the submarine dead regardless of actual reason.
				// simulation termination is handled by backend connection itself.
				m_dead = true;
			}
		}
		m_listener.broadcast(immutable CICSimFlowEndRes(res));
	}

	void handleAcousticStreamRes(AcousticStreamRes res)
	{
		CICSubAcousticRes bdcst = cast(CICSubAcousticRes) res;
		enforce(m_state.recStateInitialized);
		enforce(res.atTime == m_state.recState.subSnap.atTime);
		m_listener.broadcast(cast(immutable) bdcst);
		// waterfall analyzers
		synchronized(m_state.ctcMut)
		{
			foreach (HydrophoneData hd; res.data)
			{
				WaterfallAnalyzer al = m_wfAnalizers[hd.hydrophoneIdx];
				al.processNewData(hd, res.atTime);
				CICWaterfallUpdateRes wfu;
				wfu.hydrophoneIdx = hd.hydrophoneIdx;
				wfu.peaks = al.getPeaks();
				wfu.trackers = al.getTrackers();
				m_listener.broadcast(cast(immutable) wfu);
				ContactData[] newCdata = al.generateRayData(res.atTime);
				foreach (cd; newCdata)
					processContactData(cd);
				al.saveToDiskIfPossible();
			}
			// hydrophone slices generate tracker data, so we simply periodically
			// dump all contact data.
			m_state.saveToDiskIfPossible();
		}
	}

	void handleSonarStreamRes(SonarStreamRes res)
	{
		CICSubSonarRes bdcst;
		enforce(res.atTime == m_state.recState.subSnap.atTime);
		bdcst.data = res.data;
		m_listener.broadcast(cast(immutable) bdcst);
	}

	void handleCICEmitPingReq(CICEmitPingReq req)
	{
		synchronized(m_state.rsMut)
		{
			if (m_dead)
				return;
		}
		m_bcon.sendMessage(cast(immutable EmitPingReq) req);
	}

	/*
	Weapon management.
	*/

	void handleTubeStateUpdateRes(TubeStateUpdateRes res)
	{
		synchronized(m_state.rsMut)
		{
			m_state.handleTubeFullState(res.tube);
		}
		m_listener.broadcast(cast(immutable) CICTubeStateUpdateRes(res));
	}

	void handleAmmoRoomStateUpdateRes(AmmoRoomStateUpdateRes res)
	{
		synchronized(m_state.rsMut)
		{
			m_state.handleAmmoRoomFullState(res.room);
		}
		m_listener.broadcast(cast(immutable) CICAmmoRoomStateUpdateRes(res));
	}

	/*
	Scenario.
	*/

	void handleMapOverlayUpdateRes(MapOverlayUpdateRes res)
	{
		synchronized(m_state.rsMut)
		{
			m_state.handleMapOverlayUpdateRes(res);
		}
		m_listener.broadcast(cast(immutable) CICMapOverlayUpdateRes(res));
	}

	void handleScenarioGoalUpdateRes(ScenarioGoalUpdateRes res)
	{
		synchronized(m_state.rsMut)
		{
			m_state.handleScenarioGoalUpdateRes(res);
		}
		m_listener.broadcast(cast(immutable) CICScenarioGoalUpdateRes(res));
	}

	void handleChatMessageRes(ChatMessageRes res)
	{
		synchronized(m_state.rsMut)
		{
			m_state.handleChatMessageRes(res);
		}
		m_listener.broadcast(cast(immutable) CICChatMessageRes(res));
	}

	void handleSimulatorPausedRes(SimulatorPausedRes res)
	{
		synchronized(m_state.rsMut)
		{
			m_state.handleSimulatorPausedRes(res);
		}
		m_listener.broadcast(cast(immutable) CICSimulatorPausedRes(res.isPaused));
	}

	/*
	Contact management.
	*/

	void handleCICCreateContactFromDataReq(CICCreateContactFromDataReq req)
	{
		enforce(req.initialData.id < 0, "ContactData mus be new sample");
		enforce(req.initialData.type != DataType.Speed,
			"Cannot create contact from speed data");
		CICContactCreatedFromDataRes res;
		synchronized (m_state.ctcMut)
		{
			if (m_dead)
				return;
			Contact* ctc = m_state.createContact(req.ctcIdPrefix);
			req.initialData.ctcId = ctc.id;
			ContactData* data = m_state.updateOrCreateData(req.initialData);
			if (data is null)
				assert(0, "should not have happenned");
			m_state.initializeSolution(ctc, data);
			res.newContact = *ctc;
			res.initialData = *data;
			m_listener.broadcast(cast(immutable) res);
			m_state.saveToDiskIfPossible();
		}
	}

	void handleCICCreateContactFromHTrackerReq(CICCreateContactFromHTrackerReq req)
	{
		enforce(req.hydrophoneIdx >= 0 && req.hydrophoneIdx < m_wfAnalizers.length);
		CICContactCreatedFromHTrackerRes res;
		synchronized (m_state.ctcMut)
		{
			if (m_dead)
				return;
			Contact* ctc = m_state.createContact(req.ctcIdPrefix);
			res.newContact = *ctc;
			TrackerId tid = TrackerId(req.hydrophoneIdx, ctc.id);
			res.tracker = m_wfAnalizers[req.hydrophoneIdx].createTracker(tid, req.bearing);
			m_listener.broadcast(cast(immutable) res);
			m_state.saveToDiskIfPossible();
		}
	}

	void handleCICContactUpdateReq(MsgT)(MsgT req)
		if (isContactUpdateMsg!MsgT)
	{
		synchronized (m_state.ctcMut)
		{
			if (m_dead)
				return;
			if (m_state.updateContact(req))
			{
				m_listener.broadcast(cast(immutable) req);
				m_state.saveToDiskIfPossible();
			}
		}
	}

	private void processContactData(ContactData cd)
	{
		ContactData* data = m_state.updateOrCreateData(cd);
		if (data !is null)
		{
			CICContactDataReq res = CICContactDataReq(*data);
			m_listener.broadcast(cast(immutable) res);
			Contact* updatedContact = m_state.updateSolutionFromNewData(data);
			if (updatedContact)
			{
				m_listener.broadcast(immutable CICContactUpdateSolutionReq(
					updatedContact.id, updatedContact.solution,
					updatedContact.solutionUpdatedAt));
				m_state.saveToDiskIfPossible();
			}
		}
		// we do not throw here because contact could be deleted right after the
		// message was sent
	}

	void handleCICContactDataReq(CICContactDataReq req)
	{
		synchronized (m_state.ctcMut)
		{
			if (m_dead)
				return;
			processContactData(req.data);
		}
	}

	void handleCICDropContactReq(CICDropContactReq req)
	{
		synchronized (m_state.ctcMut)
		{
			if (m_dead)
				return;
			if (m_state.dropContact(req.ctcId))
			{
				foreach (WaterfallAnalyzer wa; m_wfAnalizers)
					wa.dropTracker(req.ctcId);
				m_listener.broadcast(cast(immutable) req);
				m_state.saveToDiskIfPossible();
			}
		}
	}

	void handleCICDropDataReq(CICDropDataReq req)
	{
		synchronized (m_state.ctcMut)
		{
			if (m_dead)
				return;
			if (m_state.dropData(req.dataId))
				m_listener.broadcast(cast(immutable) req);
		}
	}

	void handleCICContactMergeReq(CICContactMergeReq req)
	{
		enforce(req.sourceCtcId != req.destCtcId, "cannot merge into itself");
		synchronized(m_state.ctcMut)
		{
			if (m_dead)
				return;
			if (m_state.mergeContacts(req.sourceCtcId, req.destCtcId))
			{
				foreach (WaterfallAnalyzer wa; m_wfAnalizers)
					wa.mergeTrackers(req.sourceCtcId, req.destCtcId);
				m_listener.broadcast(cast(immutable) req);
				// destination contact is often updated
				Contact destCtc = m_state.getContact(req.destCtcId);
				m_listener.broadcast(immutable CICContactUpdateReq(
					destCtc.id, destCtc.type, destCtc.solution, destCtc.description));
				m_state.saveToDiskIfPossible();
			}
		}
	}

	void handleCICUpdateTrackerReq(CICUpdateTrackerReq req)
	{
		enforce(req.tracker.id.sensorIdx >= 0 &&
			req.tracker.id.sensorIdx < m_wfAnalizers.length);
		synchronized (m_state.ctcMut)
		{
			if (m_dead)
				return;
			HydrophoneTracker newState;
			if (m_wfAnalizers[req.tracker.id.sensorIdx].updateTracker(
				req.tracker.id.ctcId, req.tracker.bearing, newState))
			{
				m_listener.broadcast(immutable CICUpdateTrackerReq(newState));
			}
		}
	}

	void handleCICDropTrackerReq(CICDropTrackerReq req)
	{
		enforce(req.tid.sensorIdx >= 0 && req.tid.sensorIdx < m_wfAnalizers.length);
		synchronized (m_state.ctcMut)
		{
			if (m_dead)
				return;
			if (m_wfAnalizers[req.tid.sensorIdx].dropTracker(req.tid.ctcId))
			{
				m_listener.broadcast(req);
			}
		}
	}

	void handleCICTrimContactData(CICTrimContactData req)
	{
		synchronized (m_state.ctcMut)
		{
			if (m_dead)
				return;
			if (m_state.trimData(req.ctcId, req.olderThan))
			{
				m_listener.broadcast(req);
				m_state.saveToDiskIfPossible();
			}
		}
	}
}