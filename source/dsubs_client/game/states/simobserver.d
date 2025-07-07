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
module dsubs_client.game.states.simobserver;

import std.algorithm: min;
import std.math: floor;

import derelict.sfml2.window;
import derelict.sfml2.system;

import dsubs_common.api.messages;
import dsubs_common.api.entities;

import dsubs_client.common;
import dsubs_client.core.utils;
import dsubs_client.core.window;
import dsubs_client.input.hotkeymanager;
import dsubs_client.render.shapes;
import dsubs_client.game;
import dsubs_client.game.cameracontroller;
import dsubs_client.game.cic.messages;
import dsubs_client.game.gamestate;
import dsubs_client.game.tacoverlay;
import dsubs_client.game.states.loginscreen;
import dsubs_client.gui;


private
{
	enum int BTN_FONT = 25;
}


/// Observe and manipulate some running simulator
abstract class SimObserverState: GameState
{
	private
	{
	}

	void handleDevObserverSimulatorUpdateRes(DevObserverSimulatorUpdateRes res)
	{

	}
}