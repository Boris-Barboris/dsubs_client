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
module dsubs_client.game.connections.cicclient;

import core.thread;

import std.socket;

import dsubs_common.api;
import dsubs_common.api.protocol;
import dsubs_common.api.messages;
import dsubs_common.network.connection;

import dsubs_client.game.cic.messages;
import dsubs_client.game.cic.protocol;
import dsubs_client.common;
import dsubs_client.core.utils;
import dsubs_client.lib.openal;
import dsubs_client.game;
import dsubs_client.game.entities;
import dsubs_client.game.gamestate;
import dsubs_client.game.states.simulation;
import dsubs_client.game.states.deathscreen;


/// TCP connection to CIC server.
final class CICClientConnection: ProtocolConnection!CICProtocol
{
	this(Socket sock)
	{
		super(sock);
		this.onClose += (c)
			{
				if (Game.shuttingDown)
					return;
				trace("cic client connection onClose");
				synchronized(Game.mainMutexWriter)
				{
					// under no circumstance local CIC server should survive
					// local cic connection crash
					if (Game.cic)
						Game.cic.stop();
					Game.activeState.handleCICDisconnect();
				}
			};
		mixinHandlers(this);
	}

	private string m_url;

	@property string url() const { return m_url; }

	/// synchronous (in caller thread) connect to CIC server
	static CICClientConnection connect(string url, string password)
	{
		Socket clientSock = new Socket(AddressFamily.INET, SocketType.STREAM, ProtocolType.IP);
		scope(failure) clientSock.close();
		auto addr = parseUrl(url);
		info("Attempting to connect to CIC server ", addr);
		clientSock.connect(addr);
		auto con = new CICClientConnection(clientSock);
		con.m_url = url;
		con.start();
		con.sendMessage(immutable CICLoginReq(password));
		return con;
	}

	/// Asynchronously connect to CIC server in background thread.
	/// Returns callback that can be used to abort the attempt to connect.
	static void delegate() connectAsync(string url, string password,
		void delegate(CICClientConnection c) onSuccess,
		void delegate(Exception ex) onFailure)
	{
		info("Attempting to connect to CIC server ", url);
		Socket clientSock = new Socket(AddressFamily.INET,
			SocketType.STREAM, ProtocolType.IP);
		scope(failure) clientSock.close();
		Thread thread = new Thread(()
		{
			try
			{
				auto addr = parseUrl(url);
				clientSock.connect(addr);
				auto con = new CICClientConnection(clientSock);
				con.m_url = url;
				con.start();
				con.sendMessage(immutable CICLoginReq(password));
				onSuccess(con);
			}
			catch (Exception ex)
			{
				onFailure(ex);
			}
		}).start();
		return () { clientSock.shutdown(SocketShutdown.BOTH); clientSock.close(); };
	}

private:

	immutable(ubyte)[] awaitedDbHash;

	void h_loginRes(CICLoginRes res)
	{
		CICLoginRes expected;
		if (res.apiVersion != expected.apiVersion)
			throw new Exception("Incompatible CIC api versions. Yours: " ~
				expected.apiVersion.to!string ~ ", server: " ~ res.apiVersion.to!string);
		// let's check db versions
		bool requireDb = false;
		synchronized(Game.mainMutexWriter)
		{
			if (res.dbHash != Game.entityDbHash)
			{
				requireDb = true;
				awaitedDbHash = res.dbHash;
			}
		}
		if (requireDb)
		{
			sendMessage(immutable CICEntityDbReq());
			info("requesting entity Database from CIC server");
		}
		else
		{
			assert(Game.entityManager);
			sendMessage(immutable CICEnterSimFlowReq());
			info("entityDb found locally, entering simulation flow");
		}
	}

	void h_entityDbRes(CICEntityDbRes res)
	{
		synchronized(Game.mainMutexWriter)
		{
			Game.setEntityDb(res.res);
		}
		info("entityDb received from CIC, entering simulation flow");
		sendMessage(immutable CICEnterSimFlowReq());
	}

	void h_reconnectStateRes(CICReconnectStateRes res)
	{
		info("received reconnect state from CIC, switching to simulation state");
		synchronized(Game.mainMutexWriter)
		{
			Game.activeState = new SimulatorState(res);
		}
	}

	void h_deathRes(CICSimFlowEndRes res)
	{
		synchronized(Game.mainMutexWriter)
		{
			Game.activeState = new DeathScreenState(res);
		}
	}

	void h_SubKinematicRes(CICSubKinematicRes res)
	{
		synchronized(Game.mainMutexWriter)
		{
			Game.simState.updateLastServerTime(res.snap.atTime);
			Game.simState.playerSub.updateKinematics(res.snap);
			Game.simState.playerSub.updateWireKinematics(res.wireSnaps);
			Game.simState.gui.handleSubKinematicRes(res);
			Game.simState.tacticalOverlay.removeOldPings();
		}
	}

	void h_throttleReq(CICThrottleReq req)
	{
		synchronized(Game.mainMutexWriter)
		{
			Game.simState.playerSub.targetThrottle = req.target;
			Game.simState.gui.updateTgtThrottleDisplay(req.target);
		}
	}

	void h_courseReq(CICCourseReq req)
	{
		synchronized(Game.mainMutexWriter)
		{
			Game.simState.playerSub.targetCourse = req.target;
			Game.simState.gui.updateTgtCourseDisplay(req.target);
		}
	}

	void h_listenDirReq(CICListenDirReq req)
	{
		synchronized(Game.mainMutexWriter)
		{
			Game.simState.gui.waterfalls[req.hydrophoneIdx].listenDir = req.dir;
		}
	}

	void h_acousticRes(CICSubAcousticRes res)
	{
		synchronized(Game.mainMutexWriter)
		{
			bool[int] arrivedDataIdx;
			// broadband idx
			foreach (HydrophoneData hdata; res.data)
			{
				arrivedDataIdx[hdata.hydrophoneIdx] = true;
				foreach (AntennaeData antData; hdata.antennaes)
				{
					Game.simState.gui.waterfalls[hdata.hydrophoneIdx].drawData(
						antData.beams, hdata.rotation, antData.antennaeIdx);
				}
				Game.simState.gui.waterfalls[hdata.hydrophoneIdx].completeRow(&hdata.position);
			}
			Game.simState.contactManager.rayDataHousekeeping();
			// data-less row finalizer for hydrophones that are off
			foreach (waterfall; Game.simState.gui.waterfalls)
				if (waterfall.hydrophoneIdx !in arrivedDataIdx)
					waterfall.completeRow(null);
			// time-domain sound
			foreach (HydrophoneAudio audio; res.audio)
			{
				StreamingSoundSource s = Game.simState.sonarSounds[audio.hydrophoneIdx];
				if (s.isPlaying)
					s.setNextSample(audio.samples, audio.samplingRate);
				else
				{
					// we delay first sample enqueing in order to reduce the risk of stutter
					Game.delay( ((audio, source) => {
							source.setNextSample(audio.samples, audio.samplingRate);
						}) (audio, s),
						msecs(250), null);
				}
			}
		}
	}

	void h_sonarRes(CICSubSonarRes res)
	{
		assert(res.data.length == 1);
		assert(res.data[0].sonarIdx == 0);
		synchronized(Game.mainMutexWriter)
		{
			Game.simState.gui.sonardisp.putSliceData(res.data[0]);
			if (res.data[0].sliceId == 0)
				Game.simState.tacticalOverlay.registerPing(res.data[0].sonarIdx);
		}
	}

	void h_contactCreatedFromDataRes(CICContactCreatedFromDataRes msg)
	{
		synchronized(Game.mainMutexWriter)
		{
			Game.simState.contactManager.handleContactCreated(msg);
		}
	}

	void h_contactCreatedFromHTrackerRes(CICContactCreatedFromHTrackerRes msg)
	{
		synchronized(Game.mainMutexWriter)
		{
			Game.simState.contactManager.handleContactCreated(msg);
		}
	}

	void h_contactDataReq(CICContactDataReq msg)
	{
		synchronized(Game.mainMutexWriter)
		{
			Game.simState.contactManager.handleContactData(msg.data);
		}
	}

	void h_contactUpdateTypeReq(CICContactUpdateTypeReq msg)
	{
		synchronized(Game.mainMutexWriter)
		{
			Game.simState.contactManager.handleContactUpdate(msg);
		}
	}

	void h_contactUpdateSolutionReq(CICContactUpdateSolutionReq msg)
	{
		synchronized(Game.mainMutexWriter)
		{
			Game.simState.contactManager.handleContactUpdate(msg);
		}
	}

	void h_contactUpdateDescriptionReq(CICContactUpdateDescriptionReq msg)
	{
		synchronized(Game.mainMutexWriter)
		{
			Game.simState.contactManager.handleContactUpdate(msg);
		}
	}

	void h_contactUpdateReq(CICContactUpdateReq msg)
	{
		synchronized(Game.mainMutexWriter)
		{
			Game.simState.contactManager.handleContactUpdate(msg);
		}
	}

	void h_dropContactReq(CICDropContactReq msg)
	{
		synchronized(Game.mainMutexWriter)
		{
			Game.simState.contactManager.handleDropContact(msg.ctcId);
		}
	}

	void h_dropDataReq(CICDropDataReq msg)
	{
		synchronized(Game.mainMutexWriter)
		{
			Game.simState.contactManager.handleDropData(msg.dataId);
		}
	}

	void h_contectMergeReq(CICContactMergeReq msg)
	{
		synchronized(Game.mainMutexWriter)
		{
			Game.simState.contactManager.hadleMergeContact(msg.sourceCtcId, msg.destCtcId);
		}
	}

	void h_waterfallUpdateRes(CICWaterfallUpdateRes msg)
	{
		synchronized(Game.mainMutexWriter)
		{
			auto wto = Game.simState.gui.waterfalls[msg.hydrophoneIdx].trackerOverlay;
			wto.updatePeaks(msg.peaks);
			auto manager = Game.simState.contactManager;
			foreach (ht; msg.trackers)
				manager.handleTracker(ht);
		}
	}

	void h_updateTrackerReq(CICUpdateTrackerReq msg)
	{
		synchronized(Game.mainMutexWriter)
		{
			auto manager = Game.simState.contactManager;
			manager.handleTracker(msg.tracker);
		}
	}

	void h_dropTrackerReq(CICDropTrackerReq msg)
	{
		synchronized(Game.mainMutexWriter)
		{
			auto manager = Game.simState.contactManager;
			manager.handleDropTracker(msg.tid);
		}
	}

	void h_trimContactData(CICTrimContactData msg)
	{
		synchronized(Game.mainMutexWriter)
		{
			auto manager = Game.simState.contactManager;
			manager.handleTrimContactData(msg.ctcId, msg.olderThan);
		}
	}

	void h_tubeStateUpdateRes(CICTubeStateUpdateRes msg)
	{
		synchronized(Game.mainMutexWriter)
		{
			Game.simState.playerSub.tube(msg.res.tube.tubeId).
				updateFromFullState(msg.res.tube);
		}
	}

	void h_ammoRoomStateUpdateRes(CICAmmoRoomStateUpdateRes msg)
	{
		synchronized(Game.mainMutexWriter)
		{
			Game.simState.playerSub.ammoRoom(msg.res.room.roomId).
				updateFromFullState(msg.res.room);
		}
	}

	void h_mapOverlayUpdateRes(CICMapOverlayUpdateRes msg)
	{
		synchronized(Game.mainMutexWriter)
		{
			Game.simState.tacticalOverlay.updateScenarioElements(msg.res.mapElements);
		}
	}

	void h_scenarioGoalUpdateRes(CICScenarioGoalUpdateRes msg)
	{
		synchronized(Game.mainMutexWriter)
		{
			Game.simState.gui.handleCICScenarioGoalUpdateRes(msg);
		}
	}

	void h_chatMessageRes(CICChatMessageRes msg)
	{
		info("received chat message: ", msg.res);
		synchronized(Game.mainMutexWriter)
		{
			Game.simState.gui.handleChatMessage(msg.res.message);
		}
	}

	void h_wireDesiredLengthReq(CICWireDesiredLengthReq msg)
	{
		synchronized(Game.mainMutexWriter)
		{
			Game.simState.gui.handleCICWireDesiredLengthReq(msg);
		}
	}

	void h_simulatorPausedRes(CICSimulatorPausedRes msg)
	{
		synchronized(Game.mainMutexWriter)
		{
			Game.simState.gui.handleCICSimulatorPausedRes(msg);
		}
	}
}
