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
module dsubs_client.game.states.devmenu;

import std.algorithm;
import std.array;
import std.conv: to;
import std.math;
import std.utf;
import std.traits: EnumMembers;
import std.experimental.logger;

import core.thread;

import derelict.sfml2.window;

import dsubs_common.api;
import dsubs_common.api.messages;

import dsubs_client.core.utils;
import dsubs_client.common;
import dsubs_client.game;
import dsubs_client.game.gamestate;
import dsubs_client.game.states.loginscreen;
import dsubs_client.game.states.loadout;
import dsubs_client.game.states.simobserver;
import dsubs_client.gui;


private
{
	enum int HDR_SIZE = 40;
	enum int HDR_FONT = 30;
	enum int BTN_SIZE = 26;
	enum int BTN_FONT = 20;
	enum int SIM_FONT = 16;
}


/// Developer menu: simulator observer, balance tools...
final class DevMenuState: GameState
{
	private
	{
		SimulatorRecord[] m_simulators;
		Div m_topLevelDiv;
		Div m_simListDiv;
		Div m_footerDiv;
		ScrollBar m_simListScrollBar;
		Div m_scenListDiv;
		ScrollBar m_scenListScrollBar;
		Panel m_mainPanel;
		Button m_observeButtonToSignalClickEnd;
		__gshared AvailableScenario[] g_devScenarios;
	}

	this(SimulatorRecord[] simulators)
	{
		m_simulators = simulators;
	}

	static void registerAvailableDevScenarios(AvailableScenario[] scenarios)
	{
		g_devScenarios = scenarios;
	}

	override void handleBackendDisconnect()
	{
		error("backend connection closed");
		Game.activeState = new LoginScreenState();
	}

	override void handleCICDisconnect() {}

	void handleDevObserveSimulatorRes(DevObserveSimulatorRes res)
	{
		if (m_observeButtonToSignalClickEnd)
			m_observeButtonToSignalClickEnd.signalClickEnd();
		if (!res.success)
			return;
		Game.activeState = new SimObserverState(res);
	}

	private Div buildObservableSimRow(SimulatorRecord simRec)
	{
		Label simDescription = builder(new Label()).content(
			simRec.to!string).fontSize(SIM_FONT).build;
		Button terminateSimBtn = builder(new Button(ButtonType.ASYNC)).
			content("Terminate").fontSize(SIM_FONT).fixedSize(vec2i(120, 1)).
			backgroundColor(COLORS.simLaunchButtonBgnd).fontColor(sfBlack).build;
		Button observeSimBtn = builder(new Button(ButtonType.ASYNC)).
			content("Observe").fontSize(SIM_FONT).fixedSize(vec2i(100, 1)).
			backgroundColor(COLORS.cancelButtonBgnd).fontColor(sfBlack).build;
		Div res = builder(hDiv([simDescription, terminateSimBtn, observeSimBtn])).
			fixedSize(vec2i(500, SIM_FONT + 6)).build();

		observeSimBtn.onClick += ()
			{
				info("Requesting observation of simulator ", simRec.uniqId);
				m_observeButtonToSignalClickEnd = observeSimBtn;
				Game.bconm.con.sendMessage(immutable DevObserveSimulatorReq(simRec.uniqId));
			};

		terminateSimBtn.onClick += ()
			{
				info("Requesting termination of simulator ", simRec.uniqId);
				observeSimBtn.pressable = false;
				Game.bconm.con.sendMessage(
					immutable DevTerminateSimulatorReq(simRec.uniqId));
			};

		return res;
	}

	private Div buildSimListUi(SimulatorRecord[] simRecords)
	{
		GuiElement[] simulatorRows;
		foreach (SimulatorRecord simRec; simRecords)
			simulatorRows ~= buildObservableSimRow(simRec);
		int sbDivHeight = ((SIM_FONT + 6 + 3) * simulatorRows.length).to!int;
		m_simListDiv = builder(vDiv(simulatorRows)).
			fixedSize(vec2i(10, sbDivHeight)).backgroundColor(COLORS.simPanelBgnd).
			borderWidth(3).build();
		m_simListScrollBar = new ScrollBar(m_simListDiv);

		Label simListHeaderName = builder(new Label()).content("Simulators:").
			fontSize(BTN_FONT).fixedSize(vec2i(100, BTN_FONT + 4)).build();
		Button simListRefreshBtn = builder(new Button()).content("Refresh").
			fontSize(BTN_FONT).fixedSize(vec2i(80, BTN_FONT + 4)).build();
		simListRefreshBtn.onClick += {
			trace("refreshing simulator list");
			Game.bconm.con.sendMessage(immutable DevSimulatorsListReq());
		};

		Div simListHeader = builder(hDiv([
			simListHeaderName, filler(), simListRefreshBtn])).
			fixedSize(vec2i(1, BTN_FONT + 4)).build();

		Div res = builder(vDiv([simListHeader, m_simListScrollBar])).
			build();
		return res;
	}

	private Div buildAvailableScenarioRow(AvailableScenario scen)
	{
		Label scenDescription = builder(new Label()).content(
			scen.to!string).fontSize(SIM_FONT).build;
		Button spawnScenBtn = builder(new Button()).
			content("Spawn").fontSize(SIM_FONT).fixedSize(vec2i(100, 1)).
			backgroundColor(COLORS.cancelButtonBgnd).fontColor(sfBlack).build;
		Div res = builder(hDiv([scenDescription, spawnScenBtn])).
			fixedSize(vec2i(500, SIM_FONT + 6)).build();

		spawnScenBtn.onClick += ()
			{
				info("Requesting simulator creation from scenario ", scen.name);
				Game.bconm.con.sendMessage(immutable DevCreateSimulatorReq(scen.name));
			};

		return res;
	}

	private Div buildDevScenarioListUi(AvailableScenario[] scenarios)
	{
		GuiElement[] scenarioRows;
		foreach (AvailableScenario scen; scenarios)
			scenarioRows ~= buildAvailableScenarioRow(scen);
		int sbDivHeight = ((SIM_FONT + 6 + 3) * scenarioRows.length).to!int;
		m_scenListDiv = builder(vDiv(scenarioRows)).
			fixedSize(vec2i(10, sbDivHeight)).backgroundColor(COLORS.simPanelBgnd).
			borderWidth(3).build();
		m_scenListScrollBar = new ScrollBar(m_scenListDiv);

		Label scenListHeaderName = builder(new Label()).content("Dev scenarios:").
			fontSize(BTN_FONT).fixedSize(vec2i(150, BTN_FONT + 4)).build();

		Div scenListHeader = builder(hDiv([
			scenListHeaderName, filler()])).
			fixedSize(vec2i(1, BTN_FONT + 4)).build();

		Div res = builder(vDiv([scenListHeader, m_scenListScrollBar])).
			build();
		return res;
	}

	override void setup()
	{
		Button backToLoadountBtn = builder(new Button()).
			content("Back").fontSize(BTN_SIZE).fixedSize(vec2i(100, 1)).
			backgroundColor(COLORS.cancelButtonBgnd).fontColor(sfBlack).build;

		backToLoadountBtn.onClick += { Game.activeState = new LoadoutState(); };

		m_footerDiv = builder(hDiv([backToLoadountBtn, filler(), filler()])).
			fixedSize(vec2i(1, HDR_SIZE)).build();

		Div simListUi = buildSimListUi(m_simulators);
		Div devScenarioListUi = buildDevScenarioListUi(g_devScenarios);
		devScenarioListUi.fraction = 0.4f;

		m_topLevelDiv = vDiv([
			filler(0.05f),
			simListUi,
			devScenarioListUi,
			m_footerDiv
		]);

		m_mainPanel = new Panel(m_topLevelDiv);
		Game.guiManager.addPanel(m_mainPanel);
	}
}