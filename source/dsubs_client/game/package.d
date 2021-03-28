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
module dsubs_client.game;

import std.parallelism;

import core.sync.rwmutex;
import core.thread;
import core.memory: GC;

import dsubs_common.api;
import dsubs_common.api.marshalling;
import dsubs_common.api.messages: EntityDbRes;

import dsubs_client.common;
import dsubs_client.core.scheduler;
import dsubs_client.core.window;
import dsubs_client.lib.openal: cleanupSoundResources;
import dsubs_client.input.router;
import dsubs_client.input.hotkeymanager;
import dsubs_client.gui.manager;
import dsubs_client.render.render;
import dsubs_client.render.worldmanager;

import dsubs_client.game.gamestate;
import dsubs_client.game.connections.backend;
import dsubs_client.game.entities;
import dsubs_client.game.cic.server;
import dsubs_client.game.states.loginscreen;
import dsubs_client.game.states.loadout;
import dsubs_client.game.states.replay;
import dsubs_client.game.states.simulation;


/// Namespace for globals wich represent the game state.
class Game
{
__gshared:
	bool shuttingDown;

	Window window;
	InputRouter inputRouter;
	Render render;
	GuiManager guiManager;
	WorldManager worldManager;
	HotkeyManager hotkeyManager;
	Scheduler scheduler;

	/// Global lock, held by window message pump and render threads.
	/// When in doubt, hold this one.
	private ReadWriteMutex mainMutex;
	pragma(inline) static @property Object.Monitor mainMutexReader() { return mainMutex.reader; }
	pragma(inline) static @property Object.Monitor mainMutexWriter() { return mainMutex.writer; }

	// entity databases in different forms
	immutable(ubyte)[] entityDbHash;
	EntityDb entityDb;
	EntityManager entityManager;

	/// persistent backend connection
	BackendConMaintainer bconm;

	/// CIC
	CICServer cic;
	CICClientConnection ciccon;

	private GameState m_activeState;

	/// get current active game state object
	static @property GameState activeState() { return m_activeState; }

	/// switch game to new state
	static @property void activeState(GameState newState)
	{
		assert(newState);
		if (shuttingDown)
			return;
		if (m_activeState)
			info("STATE TRANSITION: " ~ m_activeState.classinfo.name ~ " to ",
				newState.classinfo.name);
		clearEntities();
		m_activeState = newState;
		m_activeState.setup();
	}

	static @property LoginScreenState loginScreenState()
	{
		LoginScreenState resState = cast(LoginScreenState) m_activeState;
		enforce(resState !is null,
			"game is not in loginscreen state, but in " ~ m_activeState.classinfo.name);
		return resState;
	}

	static @property LoadoutState loadoutState()
	{
		LoadoutState resState = cast(LoadoutState) m_activeState;
		enforce(resState !is null,
			"game is not in loadout state, but in " ~ m_activeState.classinfo.name);
		return resState;
	}

	static @property SimulatorState simState()
	{
		SimulatorState resState = cast(SimulatorState) m_activeState;
		enforce(resState !is null,
			"game is not in simulator state, but in " ~ m_activeState.classinfo.name);
		return resState;
	}

	static @property ReplayState replayState()
	{
		ReplayState resState = cast(ReplayState) m_activeState;
		enforce(resState !is null,
			"game is not in replay state, but in " ~ m_activeState.classinfo.name);
		return resState;
	}

	/// start the game (blocks caller thread)
	static void start(string coopAddr = null)
	{
		assert(window is null);
		window = new Window();
		inputRouter = new InputRouter(window);
		render = new Render(window, inputRouter);
		guiManager = new GuiManager(window);
		worldManager = new WorldManager(window);
		hotkeyManager = new HotkeyManager(window);
		mainMutex = new ReadWriteMutex();
		scheduler = new Scheduler();
		scheduler.start();
		scope(exit)
		{
			scheduler.stop();
			Thread.sleep(msecs(100));
			window.close();
		}
		render.guiRender = guiManager;
		render.worldRender = worldManager;
		inputRouter.guiRouter = guiManager;
		inputRouter.worldRouter = worldManager;
		inputRouter.hotkeyRouter = hotkeyManager;

		// start connection maintainer
		bconm = new BackendConMaintainer();
		scope(exit)
		{
			// connection cleanup
			info("shutting down TCP connections...");
			bconm.stop();
			if (ciccon)
				ciccon.close();
			if (cic)
				cic.stop();
			info("OK");
		}

		// setup login screen
		synchronized (mainMutexWriter)
			activeState = new LoginScreenState(coopAddr);

		// Start render thread and serve the windows event pump. Render takes
		// reader lock and has low priority.
		render.start(mainMutex.reader);
		scope(exit)
		{
			shuttingDown = true;
			render.stopAsync();
		}
		try
		{
			window.pollEvents(mainMutexWriter);
			synchronized (mainMutexWriter)
			{
				clearEntities();
			}
		}
		catch (Throwable tw)
		{
			error("window message loop crashed with ", tw.toString);
			throw tw;
		}
	}

	static void setEntityDb(EntityDb newDb)
	{
		entityDb = newDb;
		entityManager = new EntityManager(newDb);
	}

	/// clear various callbacks and objects in order to transition to another
	/// game state.
	private static void clearEntities()
	{
		cleanupSoundResources();
		inputRouter.clearFocused();
		guiManager.clearPanels();
		render.clearHandlers();
		worldManager.clear();
		hotkeyManager.clear();
		// let's free some memory after the clear
		delay(() { GC.collect(); GC.minimize(); }, msecs(500), null);
		// hotkey manager requires some additional attention
		render.onPreRender += (long usecs) { hotkeyManager.processHeldKeys(usecs); };
	}

	/// execute delegate 'what' after 'after' time interval, while holding
	/// 'mutToHold' lock.
	static void delay(void delegate() what, Duration after, Object.Monitor mutToHold)
	{
		assert(Game.scheduler !is null);
		Game.scheduler.delay(what, after, mutToHold);
	}
}