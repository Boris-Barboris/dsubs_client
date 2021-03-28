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
module dsubs_client.game.kinetic;

import std.algorithm: min, max, map;
import std.array: array;
import std.conv: to;
import std.experimental.logger;

import dsubs_common.api;
import dsubs_common.math;



/// Trace of rigid body kinematics that is updated periodically from the server
/// and is being interpolated on the client for smooth rendering purposes.
/// https://en.wikipedia.org/wiki/Cubic_Hermite_spline
struct KinematicTrace
{
	private
	{
		immutable int maxLen = 3;

		// most recent snapshots received
		KinematicSnapshot[maxLen] records;
		// number of actual snapshots in trace, from 0 to 3
		int len = 0;
		// index of the oldest snapshot in the trace
		int oldest = 0;
		// client-side interpolated state
		KinematicSnapshot curState;
		usecs_t curTime;
	}

	@property bool canInterpolate() const { return len > 0; }

	/// Append new snapshot to the trace. If the internal buffer overflows,
	/// current state jumps forward.
	void appendSnapshot(ref const KinematicSnapshot snapshot)
	{
		if (len == maxLen)
		{
			int newOldest = (oldest + 1) % maxLen;
			if (curTime < records[newOldest].atTime)
			{
				// render loop is too slow, we need to push this body forward in time
				// to keep up with the stream of updates coming from the server

				// current interpolated state is behind the snapshot
				// wich will be the new oldest one
				curState = records[newOldest];
				curTime = curState.atTime;
			}
			records[oldest] = *cast(KinematicSnapshot*) &snapshot;
			oldest = newOldest;
		}
		else
		{
			if (len == 0)
			{
				curTime = snapshot.atTime;
				curState = *cast(KinematicSnapshot*) &snapshot;
			}
			records[(oldest + len) % maxLen] = *cast(KinematicSnapshot*) &snapshot;
			len++;
		}
	}

	/// result of an interpolation
	@property const(KinematicSnapshot) result() const
	{
		assert(canInterpolate);
		return curState;
	}

	/// the most recent snapshot received
	@property const(KinematicSnapshot) mostRecent() const
	{
		assert(canInterpolate);
		return records[(oldest + len - 1) % maxLen];
	}

	/// move time forward by 'usecs' microsecods and recalculate state
	void moveForward(usecs_t fwd)
	{
		if (len < 2)	// one snapshot is not enough
			return;
		curTime = min(curTime + fwd, mostRecent.atTime);
		// now we just need to find, between which points does the
		// curTime lie
		for (int curSecond = 1; curSecond < len; curSecond++)
		{
			int i2 = (oldest + curSecond) % maxLen;
			if (curTime <= records[i2].atTime)
			{
				updateResult((oldest + curSecond - 1) % maxLen, i2);
				break;
			}
			assert(curSecond != maxLen - 1, "Impossible, should be unreachable");
		}
		curState.atTime = curTime;
	}

	private void updateResult(int i1, int i2)
	{
		double dt = (records[i2].atTime - records[i1].atTime) / 1e6;
		double t = (curTime - records[i1].atTime) / 1e6 / dt;

		curState.position = chspline(records[i1].position, records[i2].position,
			records[i1].velocity, records[i2].velocity, t, dt);
		curState.rotation = chspline(records[i1].rotation, records[i2].rotation,
			records[i1].angVel, records[i2].angVel, t, dt);
		// simple linear interpolation for velocities
		curState.velocity = records[i1].velocity +
			t * (records[i2].velocity - records[i1].velocity);
		curState.angVel = records[i1].angVel +
			t * (records[i2].angVel - records[i1].angVel);
	}

}


/// Return global velocity of the point that is fixed on rigid body's surface and is represented by child transform.
vec2d fixedPointVelocity(KinematicSnapshot kinet, Transform2D atTransform)
{
	vec2d deltaPos = atTransform.position;
	vec3d deltaPos3d = vec3d(deltaPos.x, deltaPos.y, 0.0);
	vec3d angVel3d = vec3d(0.0, 0.0, kinet.angVel);
	vec3d linearVel3d = cross(angVel3d, deltaPos3d);
	vec2d planarVel = vec2d(linearVel3d.x, linearVel3d.y);
	return planarVel + kinet.velocity;
}


/// Global reference frame version of API structure
struct WirePointSnapshotAbs
{
	/// absolute position
	vec2d position;
	vec2d velocity;
}

struct WireSnapshotAbs
{
	usecs_t atTime;
	/// world position of the attachment point
	vec2d attachPosition;
	WirePointSnapshotAbs[] points;
}


/// Trace of attached wire kinematics that is updated periodically from the server
/// and is being interpolated on the client for smooth rendering purposes.
struct WireTrace
{
	private
	{
		immutable int maxLen = 3;

		// most recent snapshots received
		WireSnapshotAbs[maxLen] records;
		// number of actual snapshots in trace, from 0 to 3
		int len = 0;
		// index of the oldest snapshot in the trace
		int oldest = 0;
		// client-side interpolated state
		WireSnapshotAbs curState;
		usecs_t curTime;
	}

	KinematicTrace* attachTrace;
	Transform2D attachTransform;

	private static WireSnapshotAbs deepCopy(const WireSnapshotAbs rhs)
	{
		return WireSnapshotAbs(rhs.atTime, rhs.attachPosition, rhs.points.dup);
	}

	@property bool canInterpolate() const { return len > 0; }

	/// Append new snapshot to the trace. If the internal buffer overflows,
	/// current state jumps forward.
	void appendSnapshot(const WireSnapshot snapshot)
	{
		WireSnapshotAbs snapshotAbs = WireSnapshotAbs(snapshot.atTime, snapshot.attachPosition);
		snapshotAbs.points = snapshot.points.map!(wps => WirePointSnapshotAbs(
			wps.position.to!vec2d + snapshot.attachPosition, wps.velocity.to!vec2d)).array;
		if (len == maxLen)
		{
			int newOldest = (oldest + 1) % maxLen;
			if (curTime < records[newOldest].atTime)
			{
				// current interpolated state is behind the snapshot
				// wich will be the new oldest one
				curState = deepCopy(records[newOldest]);
				curTime = curState.atTime;
			}
			records[oldest] = *cast(WireSnapshotAbs*) &snapshotAbs;
			oldest = newOldest;
		}
		else
		{
			if (len == 0)
			{
				curTime = snapshotAbs.atTime;
				curState = deepCopy(snapshotAbs);
			}
			records[(oldest + len) % maxLen] = *cast(WireSnapshotAbs*) &snapshotAbs;
			len++;
		}
	}

	/// result of an interpolation
	@property const(WireSnapshotAbs) result() const
	{
		assert(canInterpolate);
		return curState;
	}

	/// the most recent snapshot received
	@property const(WireSnapshotAbs) mostRecent() const
	{
		assert(canInterpolate);
		return records[(oldest + len - 1) % maxLen];
	}

	/// move time forward by 'usecs' microsecods and recalculate state
	void moveForward(usecs_t fwd)
	{
		if (len < 2)	// one snapshot is not enough
			return;
		curTime = min(curTime + fwd, mostRecent.atTime);
		// now we just need to find, between which points does the
		// curTime lie
		for (int curSecond = 1; curSecond < len; curSecond++)
		{
			int i2 = (oldest + curSecond) % maxLen;
			if (curTime <= records[i2].atTime)
			{
				updateResult((oldest + curSecond - 1) % maxLen, i2);
				break;
			}
			assert(curSecond != maxLen - 1, "Impossible, should be unreachable");
		}
		curState.atTime = curTime;
	}

	private void updateResult(int i1, int i2)
	{
		assert(attachTrace);
		assert(attachTransform);

		double dt = (records[i2].atTime - records[i1].atTime) / 1e6;
		double t = (curTime - records[i1].atTime) / 1e6 / dt;

		curState.points.length = max(
			records[i1].points.length, records[i2].points.length);

		for (size_t j = 0; j < curState.points.length; j++)
		{
			vec2d i1pos, i2pos, i1vel, i2vel;
			if (j < records[i1].points.length)
			{
				i1pos = records[i1].points[j].position;
				i1vel = records[i1].points[j].velocity;
			}
			else
			{
				// more points in i2 than in i1, extention.
				// we take attachment trace and transform
				i1pos = records[i1].attachPosition;
				i1vel = vec2d(0, 0);
			}
			if (j < records[i2].points.length)
			{
				i2pos = records[i2].points[j].position;
				i2vel = records[i2].points[j].velocity;
			}
			else
			{
				// more points in i1 than in i2, contraction.
				// we take attachment trace and transform
				i2pos = records[i2].attachPosition;
				i2vel = fixedPointVelocity(attachTrace.result, attachTransform);
			}
			curState.points[j].position = chspline(i1pos, i2pos, i1vel, i2vel, t, dt);
			// simple linear interpolation for velocities
			curState.points[j].velocity = i1vel + t * (i2vel - i1vel);
		}
	}

}