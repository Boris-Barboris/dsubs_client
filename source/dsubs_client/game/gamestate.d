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
module dsubs_client.game.gamestate;

import dsubs_common.api.messages;
import dsubs_client.game;


abstract class GameState
{
	/// Transform the Game into this state.
	/// Only called while holding Game.mainMutex.
	void setup();

	/// Called when backend connection is closed.
	void handleBackendDisconnect();

	/// Called when CIC connection is closed.
	void handleCICDisconnect();

	/// Called when backend connection receives SimulatorTerminatingRes
	void handleSimulatorTerminatingRes()
	{
		throw new Exception("Unexpected SimulatorTerminatingRes");
	}

	/// Called in multiple stages, right after successfull login and after
	void handleAvailableScenariosRes(AvailableScenariosRes res)
	{
		throw new Exception("Unexpected AvailableScenariosRes");
	}
}