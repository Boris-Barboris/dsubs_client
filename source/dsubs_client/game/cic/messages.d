/*
DSubs
Copyright (C) 2017-2025 Baranin Alexander

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

/// CIC protocol messages
module dsubs_client.game.cic.messages;

public import dsubs_common.api.constants;
public import dsubs_common.api.messages;
public import dsubs_common.api.entities;
public import dsubs_common.api.utils;

public import dsubs_client.game.cic.entities;


/// first message sent by client after connecting to CIC
struct CICLoginReq
{
	__gshared const int g_marshIdx;
	@MaxLenAttr(256) string password;	// not implemented atm
}

/// CIC server hello response that states the version
struct CICLoginRes
{
	__gshared const int g_marshIdx;
	@MaxLenAttr(32) immutable(ubyte)[] dbHash;	/// entity database hash (SHA256)
	int apiVersion = 13;
}

/// CIC client sends this to receive entity DB
struct CICEntityDbReq
{
	__gshared const int g_marshIdx;
}

/// CIC client sends this when he ensures that entity database is
/// OK and he is ready to participate in simulator message flow
struct CICEnterSimFlowReq
{
	__gshared const int g_marshIdx;
}

/*
Messages that duplicate backend protocol messages
*/

@Compressed
struct CICEntityDbRes
{
	__gshared const int g_marshIdx;
	EntityDb res;
	alias res this;
}

@Compressed
struct CICReconnectStateRes
{
	__gshared const int g_marshIdx;
	ReconnectStateRes rawState;		/// raw reconnect state from backend
	Contact[] contacts;
}

struct CICSubKinematicRes
{
	__gshared const int g_marshIdx;
	KinematicSnapshot snap;
	WireSnapshot[] wireSnaps;
}

struct CICHydrophoneDataStreamRes
{
	__gshared const int g_marshIdx;
	usecs_t atTime;
	HydrophoneData[] data;
}

struct CICHydrophoneAudioStreamRes
{
	__gshared const int g_marshIdx;
	usecs_t atTime;
	HydrophoneAudio[] audio;
}

struct CICThrottleReq
{
	__gshared const int g_marshIdx;
	float target;
}

struct CICCourseReq
{
	__gshared const int g_marshIdx;
	float target;
}

struct CICListenDirReq
{
	__gshared const int g_marshIdx;
	int hydrophoneIdx;
	float dir;
}

struct CICSubSonarRes
{
	__gshared const int g_marshIdx;
	SonarSliceData[] data;
}

struct CICEmitPingReq
{
	__gshared const int g_marshIdx;
	int sonarIdx;
	float ilevel;
}

struct CICSimFlowEndRes
{
	__gshared const int g_marshIdx;
	SimFlowEndRes res;
	alias res this;
}

/*
Weapon-related messages that are simply repeated.
*/

struct CICLoadTubeReq
{
	__gshared const int g_marshIdx;
	LoadTubeReq req;
}

struct CICSetTubeStateReq
{
	__gshared const int g_marshIdx;
	SetTubeStateReq req;
}

// proxied to backend
struct CICLaunchTubeReq
{
	__gshared const int g_marshIdx;
	LaunchTubeReq req;
}

struct CICWireGuidanceUpdateParamsReq
{
	__gshared const int g_marshIdx;
	WireGuidanceUpdateParamsReq req;
}

struct CICWireGuidanceActivateReq
{
	__gshared const int g_marshIdx;
	WireGuidanceActivateReq req;
}

struct CICWireGuidanceStateRes
{
	__gshared const int g_marshIdx;
	WireGuidanceStateRes res;
}

struct CICWireGuidanceLostRes
{
	__gshared const int g_marshIdx;
	WireGuidanceLostRes res;
}

// proxied from backend
struct CICTubeStateUpdateRes
{
	__gshared const int g_marshIdx;
	TubeStateUpdateRes res;
}

struct CICAmmoRoomStateUpdateRes
{
	__gshared const int g_marshIdx;
	AmmoRoomStateUpdateRes res;
}

@Compressed
struct CICMapOverlayUpdateRes
{
	__gshared const int g_marshIdx;
	MapOverlayUpdateRes res;
}

@Compressed
struct CICChatMessageRes
{
	__gshared const int g_marshIdx;
	ChatMessageRes res;
}

@Compressed
struct CICScenarioGoalUpdateRes
{
	__gshared const int g_marshIdx;
	ScenarioGoalUpdateRes res;
}

/*
Contact and sensor data management API.
*/

/// Sent by client to create new contact from initial data piece.
struct CICCreateContactFromDataReq
{
	__gshared const int g_marshIdx;
	char ctcIdPrefix;		/// CIC will allocate new id for the contact, wich will start with this letter
	ContactData initialData;	/// first data sample. Id and ctcId are ignored.
}

/// Broadcasted by CIC server when the new contact is created.
struct CICContactCreatedFromDataRes
{
	__gshared const int g_marshIdx;
	Contact newContact;
	ContactData initialData;
}

/// Sent by client to create new contact and a hydrophone tracker.
struct CICCreateContactFromHTrackerReq
{
	__gshared const int g_marshIdx;
	char ctcIdPrefix;
	int hydrophoneIdx;
	float bearing;
}

/// Broadcasted by CIC server when the new contact is created.
struct CICContactCreatedFromHTrackerRes
{
	__gshared const int g_marshIdx;
	Contact newContact;
	HydrophoneTracker tracker;
}

/// Request/broadcast to update contact type.
struct CICContactUpdateTypeReq
{
	__gshared const int g_marshIdx;
	ContactId id;
	ContactType type;
}

/// Request/broadcast to update contact solution.
struct CICContactUpdateSolutionReq
{
	__gshared const int g_marshIdx;
	ContactId id;
	ContactSolution solution;
	usecs_t solutionUpdatedAt;
}

/// Request/broadcast to update contact description.
struct CICContactUpdateDescriptionReq
{
	__gshared const int g_marshIdx;
	ContactId id;
	@MaxLenAttr(128) string description;
}

/// Broadcast to update all updatable fields. Is not expected from the client.
struct CICContactUpdateReq
{
	__gshared const int g_marshIdx;
	ContactId id;
	ContactType type;
	ContactSolution solution;
	@MaxLenAttr(128) string description;
	usecs_t solutionUpdatedAt;
}

template isContactUpdateMsg(MsgT)
{
	enum bool isContactUpdateMsg =
		is(MsgT == CICContactUpdateTypeReq) ||
		is(MsgT == CICContactUpdateSolutionReq) ||
		is(MsgT == CICContactUpdateDescriptionReq) ||
		is(MsgT == CICContactUpdateReq);
}

/// Sent by client to update or append new data sample to contact.
/// Broadcasted by server when new data is produced by hydrophone tracker, or
/// one of the clients has sent this message and the update/create succeeded.
struct CICContactDataReq
{
	__gshared const int g_marshIdx;
	/// data.id should be set to -1 on client for the new data sample to be appended.
	/// If id >= 0, it tries to update the data sample with the same id. ContactData can
	/// be reassigned from one contact to another using this method. Contact source and
	/// type cannot be changed.
	ContactData data;
}

/// Request/broadcast to drop contact (drops all related data).
struct CICDropContactReq
{
	__gshared const int g_marshIdx;
	ContactId ctcId;
}

/// Request/broadcast to drop contact data.
struct CICDropDataReq
{
	__gshared const int g_marshIdx;
	int dataId;
}

/// Request/broadcast to merge source contact into dest contact.
struct CICContactMergeReq
{
	__gshared const int g_marshIdx;
	ContactId sourceCtcId;
	ContactId destCtcId;
}

/// Broadcasted by CIC when it finished analyzing new acoustic slice and contains all peaks and tracker states
/// for one hydrophone
struct CICWaterfallUpdateRes
{
	__gshared const int g_marshIdx;
	int hydrophoneIdx;
	float[] peaks;
	HydrophoneTracker[] trackers;
}

/// Sent by client and then broadcasted back to update tracker's bearing
struct CICUpdateTrackerReq
{
	__gshared const int g_marshIdx;
	HydrophoneTracker tracker;
}

/// Sent by client and then broadcasted back to drop a tracker
struct CICDropTrackerReq
{
	__gshared const int g_marshIdx;
	TrackerId tid;
}

/// Sent by client and then broadcasted back to drop all data of a contact older than
/// specific time point.
struct CICTrimContactData
{
	__gshared const int g_marshIdx;
	ContactId ctcId;
	usecs_t olderThan;
}

struct CICWireDesiredLengthReq
{
	__gshared const int g_marshIdx;
	int wireIdx;
	float desiredLength = 0.0f;
}

/// Non-persistent simulators can be paused by the player
struct CICPauseSimulatorReq
{
	__gshared const int g_marshIdx;
	PauseSimulatorReq req;
}

/// Simulator broadcasts it's pause state after PauseSimulatorReq.
struct CICSimulatorPausedRes
{
	__gshared const int g_marshIdx;
	bool isPaused;
}