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
module dsubs_client.game.states.deathscreen;

import std.datetime;
import std.utf;

import core.thread;

import derelict.sfml2.window;
import derelict.sfml2.system;

import dsubs_common.api;
import dsubs_common.api.messages;

import dsubs_client.common;
import dsubs_client.core.utils;
import dsubs_client.game;
import dsubs_client.game.gamestate;
import dsubs_client.game.states.loginscreen;
import dsubs_client.game.states.loadout;
import dsubs_client.game.states.replay;
import dsubs_client.game.cic.server;
import dsubs_client.game.cic.messages;
import dsubs_client.gui;


private
{
	enum int YOU_DIED_FONTSIZE = 60;
	enum sfColor YOU_DIED_FONTCOLOR = sfColor(255, 50, 50, 255);
	enum int CAUSE_FONTSIZE = 25;
	enum int LONG_REPORT_FONTSIZE = 22;
	enum int BUTTON_FONTSIZE = 40;
}


final class DeathScreenState: GameState
{
	private
	{
		bool m_simTerminated;
		CICSimFlowEndRes m_deathRes;
		string m_simulatorId;
	}

	this(CICSimFlowEndRes deathRes, string simulatorId)
	{
		m_simulatorId = simulatorId;
		m_deathRes = deathRes;
	}

	this(string simulatorId)
	{
		m_simulatorId = simulatorId;
		m_simTerminated = true;
	}

	override void setup()
	{
		if (Game.ciccon)
			Game.ciccon.close();

		Game.window.title = "dsubs";

		string mainLabel;
		if (m_simTerminated)
			mainLabel = "Simulator was killed";
		else
		{
			final switch (m_deathRes.res.reason)
			{
				case SimFlowEndReason.death:
					mainLabel = "YOU DIED";
					break;
				case SimFlowEndReason.victory:
					mainLabel = "VICTORY";
					break;
				case SimFlowEndReason.defeat:
					mainLabel = "DEFEAT";
					break;
			}
		}
		Label youDiedLabel = builder(new Label()).content(mainLabel).
			htextAlign(HTextAlign.CENTER).fontSize(YOU_DIED_FONTSIZE).
			fontColor(YOU_DIED_FONTCOLOR).build();
		string shortReport;
		if (m_simTerminated)
			shortReport = "Simulator was terminated/abandoned";
		else
			shortReport = m_deathRes.shortReport;
		TextBox causeLabel = builder(new TextBox()).content(shortReport).
			fontSize(CAUSE_FONTSIZE).build();
		TextBox longReportLabel = builder(new TextBox()).content(m_deathRes.longReport)
			.fontSize(LONG_REPORT_FONTSIZE).build();
		ScrollBar longReportScroll = builder(new ScrollBar(longReportLabel)).
			fixedSize(vec2i(800, 200)).build();
		Button goToMainMenu;
		bool isCicClient = Game.bconm.stopped;
		if (isCicClient)
		{
			goToMainMenu = builder(new Button()).content("return to login screen").
				htextAlign(HTextAlign.CENTER).fontSize(BUTTON_FONTSIZE).build();
			goToMainMenu.onClick += () { Game.activeState = new LoginScreenState(); };
		}
		else
		{
			goToMainMenu = builder(new Button()).content("return to main menu").
				htextAlign(HTextAlign.CENTER).fontSize(BUTTON_FONTSIZE).build();
			goToMainMenu.onClick += () { Game.activeState = new LoadoutState(); };
		}

		Div textDiv = builder(vDiv([filler(0.25f), youDiedLabel, causeLabel,
			longReportScroll, goToMainMenu, filler(0.25f)])).borderWidth(20).
			fixedSize(vec2i(800, 450)).build();
		if (!isCicClient && m_simulatorId)
		{
			Button watchReplayBtn = builder(new Button()).content("watch replay").
				htextAlign(HTextAlign.CENTER).fontSize(BUTTON_FONTSIZE).build();
			watchReplayBtn.onClick += () {
				ReplayState.s_currentSimId = m_simulatorId;
				Game.bconm.con.sendMessage(immutable ReplayGetDataReq(m_simulatorId,
					(cast(Date) Clock.currTime).toISOExtString()));
			};
			textDiv.setChild(watchReplayBtn, 5);
		}
		Div screenLayout = hDiv([
			filler(),
			textDiv,
			filler()
		]);

		Game.guiManager.addPanel(new Panel(screenLayout));
	}

	override void handleBackendDisconnect()
	{
		Game.activeState = new LoginScreenState();
	}

	// these disconnects and aborts do not require immediate state switch, we can
	// continue in loadout state.

	override void handleCICDisconnect() {}

	override void handleSimulatorTerminatingRes() {}
}