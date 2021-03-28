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
module dsubs_client.game.cic.entities;

import std.container.rbtree: RedBlackTree;

import dsubs_client.common;
import dsubs_common.api.utils;


/// Tag of a ContactData union
enum DataType: byte
{
	Ray,
	Position,
	Speed
}

struct RayData
{
	vec2d origin = vec2d(0, 0);		/// sensor position at the time
	double bearing = 0.0;			/// world-space direction from origin to contact
}

struct PositionData
{
	vec2d contactPos = vec2d(0, 0);	/// world-space contact position
}

struct SpeedData
{
	double speed = 0.0;		/// absolute speed value
}

union ContactDataUnion
{
	RayData ray;
	PositionData position;
	SpeedData speed;
}

enum DataSourceType: byte
{
	Manual,
	Hydrophone,
	ActiveSonar
}

struct DataSource
{
	DataSourceType type;
	int sensorIdx;		/// index of a hydrophone/sonar, if applicable
}

/// Semantically contact id consists of capital latin letter and a number.
struct ContactId
{
	char prefix;
	int postfix;

	void toString(scope void delegate(const(char)[]) sink) const @trusted
	{
		import std.format: formattedWrite;
		sink.formattedWrite!"%c"(prefix);
		sink.formattedWrite!"%d"(postfix);
	}
}

/// Sensor data point that is related to one contact
struct ContactData
{
	int id = -1;		// globally-unique, monotonically increasing
	ContactId ctcId;
	usecs_t time;
	DataSource source;
	DataType type;
	ContactDataUnion data;
}

/// RB-tree of ContactData pointers, ordered first by time, then by id.
alias ContactDataTree = RedBlackTree!(ContactData*,
	"a.time < b.time || (a.time == b.time && a.id < b.id)", false);

/// Uniquely identifies a tracker
struct TrackerId
{
	int sensorIdx;
	ContactId ctcId;
}

enum TrackerState: byte
{
	inactive,	/// tracker is not generating ray data.
	active		/// tracker has captured the contact and is generating ray data.
}

/// CIC entity that follows contact passive trail on the waterfall
struct HydrophoneTracker
{
	TrackerId id;
	float bearing = 0.0f;	/// current world-space bearing
	TrackerState state;
}

/// Generic contact type classification
enum ContactType: byte
{
	unknown,
	environment,
	submarine,
	weapon,
	decoy
}

/// Unique tracked contact.
struct Contact
{
	ContactId id;		// unique
	@MaxLenAttr(128) string description;
	ContactType type;
	usecs_t createdAt;
	ContactSolution solution;
	usecs_t solutionUpdatedAt;
}

/// Assumed contact kinematics
struct ContactSolution
{
	/// Time pivot. Position is assumed to be specified at this time.
	usecs_t time;
	/// Solution may lie on the last known ray (ray tracking mode), or have a designated
	/// position (absolute position mode). The last mode is indicated by posAvailable = true.
	bool posAvailable;
	vec2d pos = vec2d(0, 0);
	/// Solution may or may not have velocity assigned.
	bool velAvailable;
	vec2d vel = vec2d(0, 0);
}