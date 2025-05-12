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
module dsubs_client.game.connections.backend;

import std.socket;
import std.process;
import std.datetime: Date;

import core.atomic;
import core.thread;

import dsubs_common.api;
import dsubs_common.api.protocol;
import dsubs_common.api.messages;
import dsubs_common.api.marshalling;
import dsubs_common.network.connection;

import dsubs_client.common;
import dsubs_client.game;
import dsubs_client.game.gamestate: GameState;
import dsubs_client.game.states.loadout: LoadoutState;
import dsubs_client.game.states.loginscreen: LoginScreenState;
import dsubs_client.game.states.replay: ReplayState;
import dsubs_client.game.entities;



/// TCP connection to backend dsubs server
final class BackendMainConnection: ProtocolConnection!BackendProtocol
{
	this(Socket sock)
	{
		super(sock);
		onClose += (con)
			{
				if (Game.shuttingDown)
					return;
				synchronized(Game.mainMutexWriter)
					Game.activeState.handleBackendDisconnect();
			};
		mixinHandlers(this);
	}

private:


	// pass server response to handler of a CIC server.
	static string passToCICMixin(MsgT)()
	{
		string conMethodName = "h_" ~ MsgT.stringof;
		string res = "void " ~ conMethodName ~ "(" ~ MsgT.stringof ~ " res)";
		res ~= `{
			Game.cic.handle` ~ MsgT.stringof ~ `(res);
		}`;
		return res;
	}

	void h_serverStatus(ServerStatusRes res)
	{
		synchronized(Game.mainMutexWriter)
		{
			GameState activeState = Game.activeState;
			if (cast(LoginScreenState) activeState)
				Game.loginScreenState.handleServerStatus(res);
		}
	}

	void h_replayDataRes(ReplayDataRes res)
	{
		Date date = Date.fromISOExtString(res.metricsDate);
		synchronized(Game.mainMutexWriter)
		{
			Game.activeState = new ReplayState(date, res.replaySlices);
		}
	}

	void h_loginSuccess(LoginSuccessRes res)
	{
		synchronized(Game.mainMutexWriter)
		{
			Game.loginScreenState.handleLoginSuccess(res);
		}
	}

	void h_loginFailure(LoginFailureRes res)
	{
		synchronized(Game.mainMutexWriter)
		{
			Game.loginScreenState.handleLoginFailure(res);
		}
	}

	void h_entityDb(EntityDbRes res)
	{
		synchronized(Game.mainMutexWriter)
		{
			Game.loginScreenState.handleEntityDb(res);
		}
	}

	void h_reconnectState(ReconnectStateRes res)
	{
		synchronized(Game.mainMutexWriter)
		{
			LoadoutState.handleReconnectStateRes(res);
		}
	}

	void h_availableScenariosRes(AvailableScenariosRes res)
	{
		synchronized(Game.mainMutexWriter)
		{
			Game.activeState.handleAvailableScenariosRes(res);
		}
	}

	void h_spawnFailureRes(SpawnFailureRes res)
	{
		synchronized(Game.mainMutexWriter)
		{
			Game.loadoutState.handleSpawnFailureRes(res);
		}
	}

	mixin(passToCICMixin!(SubKinematicRes));
	mixin(passToCICMixin!(HydrophoneDataStreamRes));
	mixin(passToCICMixin!(SonarStreamRes));
	mixin(passToCICMixin!(SimFlowEndRes));
	mixin(passToCICMixin!(TubeStateUpdateRes));
	mixin(passToCICMixin!(WireGuidanceStateRes));
	mixin(passToCICMixin!(WireGuidanceLostRes));
	mixin(passToCICMixin!(AmmoRoomStateUpdateRes));
	mixin(passToCICMixin!(ScenarioGoalUpdateRes));
	mixin(passToCICMixin!(MapOverlayUpdateRes));
	mixin(passToCICMixin!(ChatMessageRes));
	mixin(passToCICMixin!(SimulatorPausedRes));
	mixin(passToCICMixin!(TimeAccelerationRes));

	void h_simulatorTerminatingRes(SimulatorTerminatingRes res)
	{
		trace("SimulatorTerminatingRes received!");
		synchronized(Game.mainMutexWriter)
		{
			Game.activeState.handleSimulatorTerminatingRes();
			// eager CIC destruction to evict clients
			if (Game.cic)
				Game.cic.stop();
		}
	}
}


/// Secondary TCP connection to backend dsubs server, used to receive
/// bulky audio data.
final class BackendSecondaryConnection: ProtocolConnection!BackendProtocol
{
	this(Socket sock)
	{
		super(sock);
		mixinHandlers(this);
	}

private:

	// pass server response to handler of a CIC server.
	static string passToCICMixin(MsgT)()
	{
		string conMethodName = "h_" ~ MsgT.stringof;
		string res = "void " ~ conMethodName ~ "(" ~ MsgT.stringof ~ " res)";
		res ~= `{
			Game.cic.handle` ~ MsgT.stringof ~ `(res);
		}`;
		return res;
	}

	mixin(passToCICMixin!(HydrophoneAudioStreamRes));
}


/// Worker thread that maintains connections to the backend open.
final class BackendConMaintainer
{
	private Thread m_mainThread, m_secondaryThread;
	private shared bool exit_flag;
	private bool m_started;
	private BackendMainConnection m_con;
	private BackendSecondaryConnection m_secCon;
	private string m_secondaryConnectionSecret;

	@property BackendMainConnection con() { return m_con; }
	@property BackendSecondaryConnection secondaryCon() { return m_secCon; }

	void start()
	{
		assert(!m_started);
		trace("starting BackendConMaintainer");
		assert(m_con is null);
		exit_flag = false;
		m_mainThread = new Thread(&mainProc);
		m_mainThread.start();
		m_started = true;
	}

	void startSecondary(string secondaryConnectionSecret)
	{
		assert(m_started);
		assert(secondaryConnectionSecret);
		m_secondaryConnectionSecret = secondaryConnectionSecret;
		trace("starting secondary connection to backend");
		assert(m_secCon is null);
		m_secondaryThread = new Thread(&secondaryProc);
		m_secondaryThread.start();
	}

	void stop()
	{
		trace("stopping BackendConMaintainer");
		atomicStore(exit_flag, true);
		if (m_started && m_con)
		{
			m_con.close();
			if (m_secCon)
				m_secCon.close();
		}
	}

	@property bool stopped() const { return exit_flag; }

	private AddressInfo[] getAddrs()
	{
		AddressInfo[] addrs;
		version (prod)
		{
			addrs = getAddressInfo(
				environment.get("DSUBS_BACKEND_HOST", "borisbarboris.duckdns.org"),
				environment.get("DSUBS_BACKEND_PORT", "17955"));
		}
		else
		{
			addrs = getAddressInfo(
				environment.get("DSUBS_BACKEND_HOST", "127.0.0.1"),
				environment.get("DSUBS_BACKEND_PORT", "17855"));
		}
		if (addrs.length < 1)
			throw new Exception("no backend address could be resolved");
		return addrs;
	}

	private void mainProc()
	{
		scope(exit) m_con = null;
		while (!atomicLoad(exit_flag))
		{
			try
			{
				Socket clientSock = new Socket(AddressFamily.INET,
					SocketType.STREAM, ProtocolType.IP);
				AddressInfo[] addrs = getAddrs();
				info("Attempting to connect to backend ", addrs[0]);
				clientSock.connect(addrs[0].address);
				m_con = new BackendMainConnection(clientSock);
				m_con.start();
				m_con.sendMessage(immutable ServerStatusReq());
				m_con.join();
			}
			catch (Exception ex)
			{
				error(ex.msg);
			}
			// flood protection
			Thread.sleep(seconds(10));
		}
	}

	private void secondaryProc()
	{
		scope(exit) m_secCon = null;
		while (!atomicLoad(exit_flag))
		{
			try
			{
				Socket clientSock = new Socket(AddressFamily.INET,
					SocketType.STREAM, ProtocolType.IP);
				AddressInfo[] addrs = getAddrs();
				info("Attempting to connect to backend ", addrs[0]);
				clientSock.connect(addrs[0].address);
				m_secCon = new BackendSecondaryConnection(clientSock);
				m_secCon.start();
				m_secCon.sendMessage(immutable LoginSecondaryReq(
					m_secondaryConnectionSecret));
				m_secCon.join();
			}
			catch (Exception ex)
			{
				error(ex.msg);
			}
			// flood protection
			Thread.sleep(seconds(10));
		}
	}
}