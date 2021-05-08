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
module dsubs_client.game.states.loadout;

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
import dsubs_client.game.entities;
import dsubs_client.game.gamestate;
import dsubs_client.game.states.loginscreen;
import dsubs_client.game.states.simulation;
import dsubs_client.game.cic.server;
import dsubs_client.gui;
import dsubs_client.input.router: IInputReceiver;
import dsubs_client.input.hotkeymanager;


private
{
	enum int HDR_SIZE = 40;
	enum int HDR_FONT = 30;
	enum int BTN_SIZE = 26;
	enum int BTN_FONT = 20;
	enum int WPN_FONT = 18;
	enum int TUBE_FONT = 18;
	enum int MISSION_FONT = 18;
	enum int DESCRIPTION_FONT = 16;
	enum int TUBE_CONTENT_FONT = 14;
	enum float DESCRIPTION_VERT_FRACTION = 0.5f;
	enum sfColor INCOMPLETE_COLOR = sfColor(200, 200, 200, 255);
}


/// Scenario and loadout selection.
final class LoadoutState: GameState
{
	private
	{
		AvailableScenariosRes* availableScenarios;
		Submarine curSelectedSub;
		TextBox hullDescriptionBox;
		Button startButton;
		string curSelectedPropulsor;
		AmmoRoomTemplate[int] roomTemplates;
		int[string][int] roomLoadouts;
		string[int] tubeLoadouts;
		Label[int] roomHeaders;
		ContextMenu tubeContextMenu;
		string[] availableHulls;
		Div rightColumnDiv;
		ScrollBar rightColumnScrollbar;
		Panel m_mainPanel;
		ScrollBar m_scenDesc;
		Div m_topLevelDiv;
		Div m_footerDiv;
		Div m_missionSelectionContent;
		AvailableScenario m_selectedScenario;
		Button m_toLoadoutBtn;
	}

	// if null, will request scenarios in setup()
	this(AvailableScenariosRes* scenarios = null)
	{
		availableScenarios = scenarios;
	}

	override void handleBackendDisconnect()
	{
		error("backend connection closed");
		Game.activeState = new LoginScreenState();
	}

	override void handleCICDisconnect() {}

	private string getRoomCapacityString(int roomId)
	{
		return roomTemplates[roomId].name ~ " " ~
			roomLoadouts[roomId].byValue.sum().to!string ~ "/" ~
			roomTemplates[roomId].capacity.to!string;
	}

	private void trySetWeaponCount(int roomId, TextField field, string weaponName)
	{
		scope(exit) roomHeaders[roomId].content = getRoomCapacityString(roomId);
		if (field.content.length <= 1)	// content is C-string
		{
			field.content = "0";
			field.moveCursorToEnd();
			roomLoadouts[roomId][weaponName] = 0;
		}
		else
		{
			try
			{
				int newCount = max(0, field.content.str.to!int);
				int oldCount = roomLoadouts[roomId][weaponName];
				int roomExcess = (roomLoadouts[roomId].byValue.sum() +
					newCount - oldCount) - roomTemplates[roomId].capacity;
				if (roomExcess > 0)
					newCount -= roomExcess;
				field.content = newCount.to!string;
				roomLoadouts[roomId][weaponName] = newCount;
			}
			catch (Exception ex)
			{
				field.content = roomLoadouts[roomId][weaponName].to!string;
			}
		}
	}

	private Div buildWeaponCountDiv(int roomId, string weaponName, int initialCount)
	{
		Label weaponNameLabel = builder(new Label()).content(weaponName).
			fontSize(WPN_FONT).build;
		weaponNameLabel.onMouseEnter += (o) {
			hullDescriptionBox.content =
					Game.entityManager.weaponTemplates[weaponName].description;
		};
		TextField weaponCountField = builder(new TextField()).
			content(initialCount.to!string).fixedSize(vec2i(45, BTN_FONT)).
			fontSize(BTN_FONT).build;
		weaponCountField.onKeyReleased += (k) {
			trySetWeaponCount(roomId, weaponCountField, weaponName);
		};
		return builder(hDiv([weaponNameLabel, weaponCountField])).
			fixedSize(vec2i(200, BTN_FONT)).build();
	}

	private ContextMenu buildTubeLoadMenu(int tubeId, Button tubeContentBtn,
		const string[] allowedWeapons, vec2i mousePos)
	{
		Button chooseEmpty = builder(new Button()).
			content("empty").fontSize(TUBE_CONTENT_FONT).build;
		chooseEmpty.onClick += {
			tubeLoadouts[tubeId] = null;
			tubeContentBtn.content = "empty";
		};
		Button[] contextButtons = [chooseEmpty];
		foreach (string allowedWeapon; allowedWeapons)
		{
			Button btn = builder(new Button()).
				content(allowedWeapon).fontSize(TUBE_CONTENT_FONT).build;
			btn.onClick += ((string aw) => {
				tubeLoadouts[tubeId] = aw;
				tubeContentBtn.content = aw;
			}) (allowedWeapon);
			contextButtons ~= btn;
		}
		return contextMenu(Game.guiManager, contextButtons, Game.window.size,
			mousePos, TUBE_CONTENT_FONT + 4);
	}

	private Div buildTubeLoadDiv(int tubeId, string initialWeapon,
		const string[] allowedWeapons)
	{
		Label tubeNameLabel = builder(new Label()).
			content("tube " ~ (tubeId + 1).to!string).fontSize(TUBE_FONT).build;
		Button tubeContentButton = builder(new Button()).
			content(initialWeapon).fontSize(TUBE_FONT).
			backgroundColor(COLORS.simButtonBgnd).fixedSize(vec2i(150, BTN_FONT)).build;
		tubeContentButton.onClick += () {
			tubeContextMenu = buildTubeLoadMenu(tubeId, tubeContentButton,
				allowedWeapons, Game.window.mousePos);
		};
		return builder(hDiv([tubeNameLabel, tubeContentButton])).
			fixedSize(vec2i(200, BTN_FONT)).build();
	}

	void selectHull(string hullname, AvailableScenario* scenario)
	{
		if (curSelectedSub is null || curSelectedSub.tmpl.name != hullname)
		{
			Game.worldManager.components.length = 0;
			const SubmarineTemplate* subTmpl =
				Game.entityManager.submarineTemplates[hullname];
			const string[] propulsorNames = subTmpl.propulsors;
			assert(propulsorNames.length > 0);
			curSelectedPropulsor = propulsorNames[0];
			GuiElement[] divElements;

			// build scrollist of propulsors
			divElements ~= builder(new Label()).content("Propulsors:").
				fontSize(BTN_FONT).fontColor(COLORS.loadoutHint).
				fixedSize(vec2i(1, 30)).build;
			foreach (propName; propulsorNames)
			{
				if (!canFind(scenario.allowedEntities.propulsorNames, propName))
					continue;
				Button propSelector = builder(new Button()).content(propName).
					fontSize(BTN_FONT).fixedSize(vec2i(200, BTN_SIZE)).
					htextAlign(HTextAlign.LEFT).build();
				divElements ~= propSelector;
				propSelector.onClick += ((string pn) => ()
					{
						curSelectedPropulsor = pn;
						if (curSelectedSub)
							curSelectedSub.setPropulsor(Game.entityManager, pn);
					})(propName);
				propSelector.onMouseEnter += ((string pn) => (IInputReceiver o)
					{
						hullDescriptionBox.content =
							Game.entityManager.propTemplates[pn].description;
					})(propName);
			}
			divElements ~= filler(15);

			// build gui for ammo rooms
			roomLoadouts.clear();
			roomTemplates.clear();
			roomHeaders.clear();
			tubeLoadouts.clear();
			if (tubeContextMenu)
			{
				tubeContextMenu.rootDiv.returnMouseFocus();
				tubeContextMenu = null;
			}

			foreach (const AmmoRoomTemplate ammoRoom; subTmpl.ammoRooms)
			{
				roomTemplates[ammoRoom.id] = cast() ammoRoom;
				Label roomHeader = builder(new Label()).content(ammoRoom.name).
					fontSize(BTN_FONT).fontColor(COLORS.loadoutHint).fixedSize(vec2i(1, 30)).build;
				roomHeaders[ammoRoom.id] = roomHeader;
				divElements ~= roomHeader;
				assert(ammoRoom.allowedWeaponSet.weaponNames.length > 0);
				int[string] defaultLoadout;
				foreach (i, weaponName; ammoRoom.allowedWeaponSet.weaponNames)
				{
					// not only we are limited by hull weapon set, we are also
					// limited by the scenario
					if (!canFind(scenario.allowedEntities.weaponNames, weaponName))
						continue;
					int count = 0;
					if (ammoRoom.name == "decoy rack")
					{
						count = ammoRoom.capacity / 2;
					}
					else if (i == 0)
						count = ammoRoom.capacity;
					defaultLoadout[weaponName] = count;
					divElements ~= buildWeaponCountDiv(ammoRoom.id, weaponName, count);
				}
				roomLoadouts[ammoRoom.id] = defaultLoadout;
				roomHeader.content = getRoomCapacityString(ammoRoom.id);
				divElements ~= filler(10);
			}

			// build gui for tubes that can be loaded on spawn
			foreach (const AmmoRoomTemplate ammoRoom; subTmpl.ammoRooms)
			{
				TubeTemplate[] roomTubes = cast(TubeTemplate[]) subTmpl.tubes.filter!(
					tt => tt.roomId == ammoRoom.id && tt.loadedOnSpawn).array;
				if (roomTubes.length == 0)
					continue;
				// not only we are limited by hull weapon set, we are also
				// limited by the scenario
				const(string)[] filteredWeaponSet = ammoRoom.allowedWeaponSet.weaponNames.
					filter!(wn => canFind(scenario.allowedEntities.weaponNames, wn)).array;
				if (filteredWeaponSet.length == 0)
					continue;
				roomTubes.sort!("a.id < b.id");
				Label roomHeader = builder(new Label()).content(ammoRoom.name ~ " tubes").
					fontSize(BTN_FONT).fontColor(COLORS.loadoutHint).fixedSize(vec2i(1, 30)).build;
				divElements ~= roomHeader;
				foreach (i, const TubeTemplate tt; roomTubes)
				{
					tubeLoadouts[tt.id] = filteredWeaponSet[i % filteredWeaponSet.length];
					divElements ~= buildTubeLoadDiv(tt.id, tubeLoadouts[tt.id],
						filteredWeaponSet);
				}
				divElements ~= filler(10);
			}

			// build scrollable div that combines propulsors, racks and tubes
			int totalDivHeight = divElements.map!(e => e.size.y + 2).sum();
			Div combinedDiv = builder(vDiv(divElements)).borderWidth(2).
				fixedSize(vec2i(200, totalDivHeight)).build;
			rightColumnScrollbar = new ScrollBar(combinedDiv);
			if (rightColumnDiv)
				rightColumnDiv.setChild(rightColumnScrollbar, 0);

			curSelectedSub = new Submarine(Game.entityManager, hullname,
				curSelectedPropulsor);
			curSelectedSub.targetThrottle = 0.1f;
			curSelectedSub.transform.rotation = -PI_2;
			Game.worldManager.components ~= curSelectedSub;
		}
	}

	override void setup()
	{
		if (availableScenarios is null)
		{
			trace("requesting available scenarios");
			Game.bconm.con.sendMessage(immutable AvailableScenariosReq());
			Label loadingLabel = builder(new Label()).content("Loading scenarios...").
				fontSize(BTN_SIZE).htextAlign(HTextAlign.CENTER).
				fontColor(COLORS.defaultFont).build();
			m_mainPanel = new Panel(loadingLabel);
			Game.guiManager.addPanel(m_mainPanel);
		}
		else
			handleAvailableScenariosRes(*availableScenarios);
		// close cic client
		if (Game.ciccon)
			Game.ciccon.close();
	}

	private GuiElement buildLoadoutUi(AvailableScenario* scenario)
	{
		availableHulls = scenario.allowedEntities.controllableSubNames;

		/* Layout:
		Hull1 |	Description	| hull_props
		Hull2 |				| racks
		Hull3 |				| tubes
			  |				| Play
		*/

		hullDescriptionBox = new TextBox();
		hullDescriptionBox.fontSize = 16;

		// scrollist of available hulls
		Button[] hullButtons;
		foreach (i, hullname; availableHulls)
		{
			Button hullSelector = builder(new Button()).content(hullname).
				fontSize(BTN_FONT).fixedSize(vec2i(200, BTN_SIZE)).
				htextAlign(HTextAlign.LEFT).build();
			hullButtons ~= hullSelector;
			hullSelector.onClick += ((string hn) => { selectHull(hn, scenario); })(hullname);
			hullSelector.onClick += ((Button selectedBtn) => {
					selectedBtn.fontColor = COLORS.textFieldCursor;
					hullButtons.filter!(b => b !is selectedBtn).
						each!(b => b.fontColor = COLORS.defaultFont);
				})(hullSelector);
			auto capture = (string hn) =>
				(IInputReceiver obj)
				{
					hullDescriptionBox.content =
						Game.entityManager.submarineTemplates[hn].description;
				};
			hullSelector.onMouseEnter += capture(hullname);
			if (i == availableHulls.length - 1)
			{
				assert(curSelectedSub is null);
				// select last submarine in the list, i want stork
				hullSelector.simulateClick();
				hullSelector.onMouseEnter(null);
				hullSelector.onMouseLeave(null);
				assert(curSelectedSub !is null);
			}
		}

		Div hullDiv = builder(vDiv(cast(GuiElement[]) hullButtons)).
			layoutType(LayoutType.CONTENT).
			size(vec2i(200, BTN_SIZE * availableHulls.length.to!int +
							availableHulls.length.to!int)).build;
		ScrollBar hullsScrollbar = new ScrollBar(hullDiv);

		startButton = builder(new Button(ButtonType.ASYNC)).fontSize(HDR_FONT).
			htextAlign(HTextAlign.CENTER).content("Start").fixedSize(vec2i(150, HDR_SIZE)).
			backgroundColor(COLORS.simLaunchButtonBgnd).fontColor(sfBlack).
			build();
		startButton.onClick += ()
			{
				if (curSelectedSub is null)
				{
					hullDescriptionBox.content = "You must select a submarine!";
					startButton.signalClickEnd();
					return;
				}
				// we can send spawn request to the server
				immutable SpawnReq req = immutable SpawnReq(
					curSelectedSub.tmpl.name, curSelectedPropulsor,
					roomLoadouts.byKey.map!(roomId =>
						AmmoRoomFullState(
							roomId,
							roomLoadouts[roomId].byKey.map!(weaponName =>
								WeaponCount(
									weaponName,
									roomLoadouts[roomId][weaponName]
								)).array
						)).array,
					tubeLoadouts.byKeyValue.map!(pair =>
						TubeSpawnState(pair.key, pair.value)).array,
					scenario.type == ScenarioType.persistentSimulator ?
						SpawnRequestType.existingSimulator : SpawnRequestType.newSimulator,
					scenario.type == ScenarioType.persistentSimulator ?
						scenario.simulatorId : scenario.name
					);
				trace("Requesting spawn: ", req);
				Game.bconm.con.sendMessage(req);
			};

		m_footerDiv.setChild(startButton, 2);

		// button to return to mission selection
		Button backToMissionBtn = builder(new Button()).fontSize(HDR_FONT).
			htextAlign(HTextAlign.CENTER).content("Cancel").fixedSize(vec2i(150, HDR_SIZE)).
			backgroundColor(COLORS.cancelButtonBgnd).fontColor(sfBlack).
			build();

		backToMissionBtn.onClick += {
			m_footerDiv.setChild(filler(), 0);
			// activate 'to loadout' button in the footer
			m_footerDiv.setChild(m_toLoadoutBtn, 2);
			m_topLevelDiv.setChild(m_missionSelectionContent, 1);
			Game.worldManager.clear();
			curSelectedSub = null;
		};

		m_footerDiv.setChild(backToMissionBtn, 0);

		Game.hotkeyManager.setHotkey(Hotkey(sfKeyReturn),
			() { startButton.simulateClick(); });

		rightColumnDiv = builder(vDiv([
				rightColumnScrollbar
				])
			).fixedSize(vec2i(250, 1)).build();

		auto loadoutDiv = hDiv([
			builder(vDiv([
						builder(new Label()).content("Hulls:").
							fontSize(BTN_FONT).fontColor(COLORS.loadoutHint).
							fixedSize(vec2i(1, 30)).build,
						hullsScrollbar
					])
				).fixedSize(vec2i(150, 1)).build(),
			filler(20),
			vDiv([
				builder(new Label()).fontSize(BTN_FONT).
					fixedSize(vec2i(1, BTN_SIZE)).fontColor(COLORS.loadoutHint).
					content("Description").build,
				new ScrollBar(hullDescriptionBox)
			]),
			filler(20),
			rightColumnDiv
		]);

		return loadoutDiv;
	}

	private Button buildScenarioSelectionBtn(AvailableScenario scen)
	{
		// generate scenario selection buttons
		Button btn = builder(new Button()).content(scen.name).
			fontSize(MISSION_FONT).fixedSize(vec2i(1, MISSION_FONT + 6)).
			build();
		if (!scen.completed)
			btn.fontColor = INCOMPLETE_COLOR;
		btn.onClick += {
			// on click we generate scenario description text box.
			string descContent = scen.name ~ "\n\n" ~ scen.shortDescription ~
				"\n\n" ~ scen.fullDescription;
			TextBox descBox = builder(new TextBox()).fontSize(DESCRIPTION_FONT).
				content(descContent).build();
			m_scenDesc = builder(new ScrollBar(descBox)).
				fraction(DESCRIPTION_VERT_FRACTION).build();
			m_selectedScenario = scen;
			(cast(Div) m_topLevelDiv.children[1]).setChild(m_scenDesc, 1);
			// activate 'to loadout' button in the footer
			m_footerDiv.setChild(m_toLoadoutBtn, 2);
		};
		return btn;
	}

	private Button buildCampaignNameButton(AvailableCampaign campaign)
	{
		// generate scenario selection buttons
		Button btn = builder(new Button()).content(campaign.name).
			fontSize(MISSION_FONT).fixedSize(vec2i(1, MISSION_FONT + 6)).
			htextAlign(HTextAlign.LEFT).build();
		if (!campaign.completed)
			btn.fontColor = INCOMPLETE_COLOR;
		btn.onClick += {
			// on click we generate campaign description text box.
			string descContent = campaign.name ~ "\n\n" ~ campaign.description;
			TextBox descBox = builder(new TextBox()).fontSize(DESCRIPTION_FONT).
				content(descContent).build();
			m_scenDesc = builder(new ScrollBar(descBox)).
				fraction(DESCRIPTION_VERT_FRACTION).build();
			(cast(Div) m_topLevelDiv.children[1]).setChild(m_scenDesc, 1);
			// deactivate 'to loadout' button in the footer
			m_footerDiv.setChild(filler(), 2);
		};
		return btn;
	}

	private void buildScenarioSelectionUi()
	{
		AvailableScenario[][ScenarioType] scenarioGroups;
		scenarioGroups[ScenarioType.standalone] = [];
		scenarioGroups[ScenarioType.tutorial] = [];
		scenarioGroups[ScenarioType.persistentSimulator] = [];
		AvailableCampaign[] campaigns;

		foreach (AvailableScenario scen; availableScenarios.scenarios)
			scenarioGroups[scen.type] ~= scen;
		campaigns = availableScenarios.campaigns;

		Label[] missionTypeLabels;
		Div[] missionTypeColumns;
		foreach (scenType; EnumMembers!ScenarioType)
		{
			string content;
			final switch (scenType)
			{
				case ScenarioType.persistentSimulator:
					content = "Online arenas";
					break;
				case ScenarioType.tutorial:
					content = "Tutorials";
					break;
				case ScenarioType.campaignMission:
					content = "Campaigns";
					break;
				case ScenarioType.standalone:
					content = "Singleplayer";
					break;
			}
			Label typeLabel = builder(new Label()).fontSize(BTN_FONT).
				htextAlign(HTextAlign.CENTER).
				fixedSize(vec2i(1, BTN_SIZE + 10)).content(content).build();
			missionTypeLabels ~= typeLabel;
			GuiElement[] missionButtons;
			if (scenType != ScenarioType.campaignMission)
			{
				AvailableScenario[] scens = scenarioGroups[scenType];
				// lexicographic sort
				// sort!((a, b) => a.name < b.name)(scens);
				foreach (AvailableScenario scen; scens)
					missionButtons ~= buildScenarioSelectionBtn(scen);
			}
			else
			{
				// handle campaigns with nested scenarios
				foreach (AvailableCampaign camp; campaigns)
				{
					missionButtons ~= buildCampaignNameButton(camp);
					foreach (AvailableScenario scen; camp.scenarios)
						missionButtons ~= buildScenarioSelectionBtn(scen);
				}
			}
			if (missionButtons.length == 0)
				missionButtons ~= filler(10);
			int sbDivHeight = ((MISSION_FONT + 6 + 4) * missionButtons.length).to!int;
			Div missionsDiv = builder(vDiv(missionButtons)).
				fixedSize(vec2i(10, sbDivHeight)).backgroundColor(COLORS.simPanelBgnd).
				borderWidth(4).build();
			ScrollBar missionsSb = new ScrollBar(missionsDiv);

			missionTypeColumns ~= vDiv([
				typeLabel,
				missionsSb
			]);
		}

		m_toLoadoutBtn = builder(new Button()).fontSize(HDR_FONT).
			backgroundColor(COLORS.simLaunchButtonBgnd).fontColor(sfBlack).
			fixedSize(vec2i(180, HDR_SIZE)).content("To loadout").build();

		m_toLoadoutBtn.onClick += {
			// we now build the loadout UI.
			GuiElement loadoutUi = buildLoadoutUi(&m_selectedScenario);
			m_topLevelDiv.setChild(loadoutUi, 1);
		};

		m_missionSelectionContent = vDiv([
			builder(hDiv([filler(20)] ~ cast(GuiElement[]) missionTypeColumns ~
				 [filler(20)])).build(),
			// here should lie a mission description
			filler(DESCRIPTION_VERT_FRACTION)
		]);
	}

	override void handleAvailableScenariosRes(AvailableScenariosRes res)
	{
		if (m_mainPanel !is null)
			Game.guiManager.removePanel(m_mainPanel);

		m_footerDiv = builder(hDiv([filler(), filler(), filler()])).
			fixedSize(vec2i(1, HDR_SIZE)).build();

		availableScenarios = new AvailableScenariosRes();
		*availableScenarios = res;
		buildScenarioSelectionUi();

		m_topLevelDiv = vDiv([
			filler(0.08f),
			m_missionSelectionContent,
			m_footerDiv
		]);

		m_mainPanel = new Panel(m_topLevelDiv);
		Game.guiManager.addPanel(m_mainPanel);
		Game.worldManager.camCtx.camera.zoom = 10.0;
		Game.worldManager.camCtx.camera.center = vec2d(0.0, 0.0);

		Game.render.onPreRender += (delta) {
			int wndX = Game.window.size.x;
			Game.worldManager.camCtx.camera.zoom = wndX / 120.0f;
		};
	}

	// shared by loginscreen and this state
	static void handleReconnectStateRes(ReconnectStateRes res)
	{
		// we need to create new CIC server
		if (Game.cic)
			Game.cic.stop();
		info("building new CIC server");
		Game.cic = new CICServer("", Game.bconm.con);
		info("starting CIC");
		Game.cic.start();
		info("connecting to local CIC");
		ushort port = Game.cic.listener.port;
		Game.ciccon = CICClientConnection.connect("127.0.0.1:" ~ port.to!string, "");
		// CIC client will perform simulator bootstrap from here, will broadcast
		// reconnect message to cic clients, and this window's cic client will
		// switch game state to Simulator.
		Game.cic.handleReconnectStateRes(res);
	}

	void handleSpawnFailureRes(SpawnFailureRes res)
	{
		hullDescriptionBox.content = "Spawn failed: " ~ res.reason;
		startButton.signalClickEnd();
	}

}