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
module dsubs_client.app;

import core.stdc.stdlib;

import std.getopt;

import dsubs_client.common;
import dsubs_client.lib.sfml;
import dsubs_client.lib.openal;
import dsubs_client.lib.fonts;
import dsubs_client.tests;
import dsubs_client.game;

version(Windows)
{
	extern(Windows) int SetConsoleOutputCP(uint);
}

/// Entrypoint
void main(string[] argv)
{
	version(Windows)
	{
		SetConsoleOutputCP(65001);
	}
	version(unittest) info("Unit tests OK");
	string coopAdr;
	getopt(argv, "coop", &coopAdr);
	version(linux)
	{
		initXLib();
	}
	loadSfmlLibraries();
	loadAudioLib();
	loadGlobalFonts();
	// runModuleTests();
	// testGuiElements();
	scope(exit) unloadAudioLib();
	try
	{
		Game.start(coopAdr);
	}
	catch (Throwable t)
	{
		error(t.toString);
		throw t;
	}
}
