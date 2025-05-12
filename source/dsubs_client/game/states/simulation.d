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
module dsubs_client.game.states.simulation;

import std.algorithm;
import std.array;
import std.range: enumerate, retro;
import std.datetime: unixTimeToStdTime, DateTime, SysTime;
import std.format;
import std.process: spawnProcess, Config;

import core.time;

import derelict.sfml2.window;
import derelict.sfml2.graphics: sfColor;

import dsubs_common.math;
import dsubs_common.containers.array;

import dsubs_client.common;
import dsubs_client.game;
import dsubs_client.gui;
import dsubs_client.input.hotkeymanager;
import dsubs_client.game.gamestate;
import dsubs_client.game.entities;
import dsubs_client.game.states.loginscreen;
import dsubs_client.game.states.deathscreen;
import dsubs_client.game.cic.messages;
import dsubs_client.game.cameracontroller;
import dsubs_client.game.tacoverlay;
import dsubs_client.game.wireui;
import dsubs_client.game.contacts;
import dsubs_client.game.waterfall;
import dsubs_client.game.sonardisp;
import dsubs_client.game.tubeui;
import dsubs_client.lib.openal;


final class SimulatorState: GameState
{
	this(CICReconnectStateRes recState)
	{
		this.m_recState = recState;
	}

	private
	{
		CICReconnectStateRes m_recState;
	}

	mixin Readonly!(Submarine, "playerSub");
	mixin Readonly!(CameraController, "camController");
	mixin Readonly!(SimulationGUI, "gui");
	mixin Readonly!(StreamingSoundSource[], "sonarSounds");
	mixin Readonly!(StreamingSoundSource, "activeSonarSound");
	mixin Readonly!(usecs_t, "lastServerTime");
	mixin Readonly!(ContactOverlayShapeCahe, "contactOverlayShapeCache");
	mixin Readonly!(ClientContactManager, "contactManager");
	mixin Readonly!(TacticalOverlay, "tacticalOverlay");
	mixin Readonly!(PlayerSubIcon, "playerSubIcon");

	@property bool isPaused() const { return m_recState.rawState.isPaused; }

	@property short timeAccelerationFactor() const
	{
		return m_recState.rawState.timeAccelerationFactor;
	}

	private
	{
		float[StreamingSoundSource] m_savedSoundGains;
		WireGuidedWeaponIcon[string] m_wireGuidedIcons;
	}

	@property void activeSonarSound(StreamingSoundSource rhs)
	{
		if (m_activeSonarSound !is rhs)
		{
			if (m_activeSonarSound)
			{
				m_savedSoundGains[m_activeSonarSound] = m_activeSonarSound.gain;
				m_activeSonarSound.gain = 0.0f;
			}
			if (rhs)
			{
				rhs.gain = m_savedSoundGains[rhs];
			}
			m_activeSonarSound = rhs;
		}
	}

	void handleWireGuidanceFullState(WireGuidanceFullState res)
	{
		if (res.wireGuidanceId !in m_wireGuidedIcons)
		{
			Tube tube = m_playerSub.getTubeByWireGuidanceId(res.wireGuidanceId);
			enforce(tube !is null, "No tube has this wire guidance");
			// new wire-guided weapon
			WireGuidedWeapon wpn = new WireGuidedWeapon(Game.entityManager,
				res.wireGuidanceId, tube, res.weaponParams);
			wpn.lastState = res;
			Game.worldManager.components ~= wpn;
			// create new overlay element for it
			WireGuidedWeaponIcon icon = new WireGuidedWeaponIcon(
				m_tacticalOverlay, wpn);
			m_wireGuidedIcons[res.wireGuidanceId] = icon;
			// find tube ui and create wire-guidance params for it
			gui.tubeUis[tube.id].recreateWireGuidance(wpn);
		}
		else
		{
			WireGuidedWeaponIcon icon =
				m_wireGuidedIcons[res.wireGuidanceId];
			WireGuidedWeapon wpn = icon.wireGuidedWeapon;
			wpn.updateKinematics(res.weaponSnap);
			wpn.lastState = res;
		}
	}

	void handleWireGuidanceUpdateParamsReq(WireGuidanceUpdateParamsReq req)
	{
		if (req.wireGuidanceId !in m_wireGuidedIcons)
			return;
		WireGuidedWeaponIcon icon = m_wireGuidedIcons[req.wireGuidanceId];
		WireGuidedWeapon wpn = icon.wireGuidedWeapon;
		TubeUI tubeUi = gui.tubeUis[wpn.tubeId];
		foreach (WeaponParamValue param; req.weaponParams)
		{
			if (param.type in wpn.weaponParams)
			{
				wpn.weaponParams[param.type] = param;
				tubeUi.updateWireGuidanceParamFromWeapon(param.type);
			}
		}
	}

	void handleWireGuidanceLostRes(WireGuidanceLostRes res)
	{
		if (res.wireGuidanceId in m_wireGuidedIcons)
		{
			WireGuidedWeaponIcon icon =
				m_wireGuidedIcons[res.wireGuidanceId];
			WireGuidedWeapon wpn = icon.wireGuidedWeapon;
			Game.worldManager.components.removeFirstUnstable(wpn);
			icon.drop();
			gui.tubeUis[wpn.tubeId].cutWireGuidance();
		}
	}

	private MonoTime m_lastServerTimeOnClient;

	@property MonoTime lastServerTimeOnClient() const { return m_lastServerTimeOnClient; }

	@property usecs_t extrapolatedServerTime() const
	{
		return m_lastServerTime +
			max(0,
				(Game.render.frameStartTime - Game.simState.lastServerTimeOnClient).
					total!"usecs") * timeAccelerationFactor / 10;
	}

	override void setup()
	{
		ReconnectStateRes rawRecState = m_recState.rawState;

		// create submarine
		m_playerSub = new Submarine(
			Game.entityManager, rawRecState.submarineName, rawRecState.propulsorName);
		m_playerSub.targetCourse = rawRecState.targetCourse;
		m_playerSub.targetThrottle = rawRecState.targetThrottle;
		m_playerSub.updateKinematics(rawRecState.subSnap);
		Game.worldManager.components ~= m_playerSub;

		// set up camera
		Game.worldManager.camCtx.camera.center = rawRecState.subSnap.position;
		Game.worldManager.camCtx.camera.zoom = 10.0;
		Game.worldManager.timeAccelerationFactor = rawRecState.timeAccelerationFactor;
		m_camController = new CameraController(Game.worldManager.camCtx.camera);

		// set tactical overlay
		m_tacticalOverlay = new TacticalOverlay(m_camController);
		Game.guiManager.addPanel(new Panel(m_tacticalOverlay));
		m_playerSubIcon = new PlayerSubIcon(m_tacticalOverlay, m_playerSub);
		m_tacticalOverlay.updateScenarioElements(rawRecState.mapElements);

		bool isCicClient = Game.bconm.stopped;
		m_gui = new SimulationGUI(
			rawRecState.canAbandon && !isCicClient, rawRecState.canBePaused);
		foreach (i, listenDir; rawRecState.listenDirs)
			m_gui.waterfalls[i].listenDir = listenDir;
		foreach (i, desiredLength; rawRecState.desiredWireLenghts)
			m_gui.wireUis[i].updateDesiredLength(desiredLength);
		m_gui.handleSubKinematicRes(cast(CICSubKinematicRes) rawRecState.subSnap);
		if (rawRecState.lastChatLogs)
			m_gui.handleChatMessage(rawRecState.lastChatLogs[$-1]);

		// ammo room and tube initialization
		foreach (AmmoRoomFullState roomState; rawRecState.ammoRoomStates)
			m_playerSub.ammoRoom(roomState.roomId).updateFromFullState(roomState);
		foreach (TubeFullState tubeState; rawRecState.tubeStates)
			m_playerSub.tube(tubeState.tubeId).updateFromFullState(tubeState);

		foreach (i; 0 .. m_playerSub.tmpl.hydrophones.length)
		{
			m_sonarSounds ~= new StreamingSoundSource();
			m_sonarSounds[$-1].normalize = true;
			m_savedSoundGains[m_sonarSounds[$-1]] = 1.0f;
		}
		m_contactOverlayShapeCache = new ContactOverlayShapeCahe();
		m_contactManager = new ClientContactManager(
			m_recState, m_playerSub.tmpl.hydrophones.length.to!int);

		foreach (wgs; rawRecState.wireGuidanceStates)
			handleWireGuidanceFullState(wgs);
	}

	override void handleBackendDisconnect()
	{
		Game.activeState = new LoginScreenState();
	}

	override void handleCICDisconnect()
	{
		error("CIC connection lost");
		Game.activeState = new LoginScreenState();
	}

	void updateLastServerTime(usecs_t newTime)
	{
		m_lastServerTime = newTime;
		m_lastServerTimeOnClient = MonoTime.currTime;
	}

	override void handleSimulatorTerminatingRes()
	{
		error("SimulatorTerminatingRes received, jumping to death screen");
		Game.activeState = new DeathScreenState();
	}
}


private
{
	enum int TAB_SIZE = 28;
	enum int BIG_BTN_FONT = 24;
	enum int BTN_FONT = 20;
	enum int MSG_FONT = 16;
	enum int OBJECTIVES_FONT_SIZE = 16;
	enum int GOAL_TEXT_SIZE = 13;
}


final class SimulationGUI
{

	private
	{
		Label curCourse, curSpeed;
		Label m_mainHintLabel;
		Panel m_mainHintPanel;
		Object m_mainHintOwner;
		void delegate() m_onMainHintHidden;
		TextField tgtCourseField, tgtThrottleField;
		TextBox chatMessageBox;
		WaterfallGui[] m_passiveGuis;
		SonarGui m_sonarGui;
		Div m_topLevelDiv;
		Div m_objectivesVdiv;
		Div m_divWithLeftPad;
		TubeUI[int] tubeUis;
		WireUi[] m_wireUis;
		Button m_abandonBtn;
		Button m_pauseBtn;
		Button m_timeAccelBtn;
	}

	@property WireUi[] wireUis() { return m_wireUis; }

	/// Sets main hint label content to labelContent and records
	/// the owner of the label. When this particular hint is overwritten or hidden in any way,
	/// onHintHidden will be called.
	void showMainHint(Object hintOwner, string labelContent, void delegate() onHintHidden = null)
	{
		if (m_mainHintOwner !is hintOwner)
		{
			if (m_onMainHintHidden)
				m_onMainHintHidden();
		}
		m_mainHintLabel.content = labelContent;
		m_mainHintOwner = hintOwner;
		m_onMainHintHidden = onHintHidden;
		if (m_mainHintPanel.added)
			return;
		Game.guiManager.addPanel(m_mainHintPanel);
	}

	/// hides main hint, but only if it is owned by the owner
	void hideMainHint(Object hintOwner)
	{
		if (hintOwner is m_mainHintOwner && m_mainHintPanel.added)
		{
			if (m_onMainHintHidden)
				m_onMainHintHidden();
			m_mainHintOwner = null;
			m_onMainHintHidden = null;
			Game.guiManager.removePanel(m_mainHintPanel);
		}
	}

	@property auto waterfalls() { return m_passiveGuis.map!(wfgui => wfgui.wf); }
	@property SonarDisplay sonardisp() { return m_sonarGui.sonar; }

	void handleSubKinematicRes(CICSubKinematicRes res)
	{
		// course
		curCourse.format!"course: %.1f"(-res.snap.rotation.compassAngle.rad2dgr);
		// speed
		vec2d vel = cast(vec2d) res.snap.velocity;
		vec2d fwd = courseVector(res.snap.rotation);
		double proj = dot(vel, fwd);
		curSpeed.format!"speed: %.2f"(proj);
		// pass to other classes that need it
		m_sonarGui.sonar.handleSubKinematicRes(res);
	}

	void handleChatMessage(ChatMessage msg)
	{
		auto stdTime = SysTime(unixTimeToStdTime(msg.sentOnUtc));
		chatMessageBox.content = "[" ~ (cast(DateTime) stdTime).timeOfDay.to!string ~
			"]: " ~ msg.message;
	}

	void updateTgtCourseDisplay(float newTgt)
	{
		tgtCourseField.content = format("%.1f", -newTgt.compassAngle.rad2dgr);
	}

	void updateTgtThrottleDisplay(float newTgt)
	{
		tgtThrottleField.content = format("%.1f", 100.0f * newTgt);
	}

	void handleCICListenDirReq(CICListenDirReq req)
	{
		m_passiveGuis[req.hydrophoneIdx].wf.listenDir = req.dir;
	}

	void handleCICWireDesiredLengthReq(CICWireDesiredLengthReq req)
	{
		m_wireUis[req.wireIdx].updateDesiredLength(req.desiredLength);
	}

	/// mapping from id of the goal to it's index in m_goalListDiv
	private Collapsable[string] m_goalIdToCollapsable;

	private Collapsable buildCollapsableForGoal(ScenarioGoal goal)
	{
		TextBox longDescBox = builder(new TextBox()).
				content(goal.longDescription).fontSize(GOAL_TEXT_SIZE).build;
		Collapsable res = builder(new Collapsable(longDescBox, goal.shortText)).
			layoutType(LayoutType.CONTENT).build();
		// we expand task list on main window by default.
		if (Game.cic)
			res.toggleCollapsed();
		return res;
	}

	private Div buildGoalListDiv(ScenarioGoal[] goals)
	{
		GuiElement[] goalCollapsables;
		goalCollapsables ~= filler();
		foreach (ScenarioGoal goal; retro(goals))
		{
			if (goal.status != ScenarioGoalStatus.unreached)
				continue;
			goalCollapsables ~= buildCollapsableForGoal(goal);
			m_goalIdToCollapsable[goal.id] = cast(Collapsable) goalCollapsables[$-1];
		}
		Div goalListDiv = builder(vDiv(cast(GuiElement[]) goalCollapsables)).
			layoutType(LayoutType.CONTENT)
			.borderWidth(3).build();
		m_divWithLeftPad = builder(hDiv([filler(6), goalListDiv])).
			layoutType(LayoutType.CONTENT).contentLayoutIgnoreFixed(true).build();
		Collapsable res = builder(new Collapsable(m_divWithLeftPad, "Objectives:")).
			backgroundColor(COLORS.simOverlayDivBgnd).
			headerFontSize(OBJECTIVES_FONT_SIZE).
			layoutType(LayoutType.CONTENT).build;
		// we expand task list on main window by default.
		if (Game.cic)
			res.toggleCollapsed();
		return res;
	}

	void handleCICSimulatorPausedRes(CICSimulatorPausedRes res)
	{
		if (m_pauseBtn is null)
			return;
		Game.simState.m_recState.rawState.isPaused = res.isPaused;
		m_pauseBtn.signalClickEnd();
		m_pauseBtn.content = pauseBtnContent(res.isPaused);
	}

	void handleCICTimeAccelerationRes(CICTimeAccelerationRes res)
	{
		if (m_timeAccelBtn is null)
			return;
		enforce(res.res.timeAccelerationFactor > 0, "invalid accel factor");
		Game.simState.m_recState.rawState.timeAccelerationFactor =
			res.res.timeAccelerationFactor;
		Game.worldManager.timeAccelerationFactor = res.res.timeAccelerationFactor;
		m_timeAccelBtn.content = timeAccelBtnContent(res.res.timeAccelerationFactor);
	}

	void handleCICScenarioGoalUpdateRes(CICScenarioGoalUpdateRes msg)
	{
		// rebuild list of collapsables while updating existing ones
		Collapsable[] goalCollapsables;
		Collapsable[string] newDict;
		foreach (ScenarioGoal goal; retro(msg.res.goals))
		{
			if (goal.status != ScenarioGoalStatus.unreached)
				continue;
			if (goal.id in m_goalIdToCollapsable)
			{
				Collapsable c = m_goalIdToCollapsable[goal.id];
				c.title = goal.shortText;
				(cast(TextBox) c.child).content = goal.longDescription;
				goalCollapsables ~= c;
			}
			else
				goalCollapsables ~= buildCollapsableForGoal(goal);
			newDict[goal.id] = goalCollapsables[$-1];
		}
		m_goalIdToCollapsable = newDict;
		Div goalListDiv = builder(vDiv(cast(GuiElement[]) goalCollapsables)).
			layoutType(LayoutType.CONTENT)
			.borderWidth(3).build();
		m_divWithLeftPad.setChild(goalListDiv, 1);
	}

	private static string pauseBtnContent(bool isPaused)
	{
		// these are supported by LiberationMono-Regular.ttf
		if (isPaused)
			return "\u25ba";
		else
			return "\u05f0";
	}

	private static string timeAccelBtnContent(short factor)
	{
		return format("x%g", factor / 10.0f);
	}

	this(bool canAbandon, bool canPause)
	{
		Submarine playerSub = Game.simState.playerSub;

		// Tabs at the top of the screen

		Button[] tabs;

		if (canAbandon)
		{
			// abandon sim button
			m_abandonBtn = builder(new Button(ButtonType.ASYNC)).content("X").
				fixedSize(vec2i(TAB_SIZE, TAB_SIZE)).fontSize(BIG_BTN_FONT).
				backgroundColor(COLORS.simLaunchButtonBgnd).build;
			m_abandonBtn.onClick += {
				startYesNoDialog("Confirm abandon scenario",
					{
						trace("sending request to abandon scenario");
						Game.bconm.con.sendMessage(immutable AbandonReq());
					},
					{
						m_abandonBtn.signalClickEnd();
					},
					360);
			};
			tabs ~= m_abandonBtn;
		}

		Button tacticalTab = builder(new Button()).content("F1 Tactical").
			fontSize(BIG_BTN_FONT).build;
		Button[] hydrophoneTabs;
		int tabId = 2;
		foreach (const HydrophoneTemplate ht; playerSub.tmpl.hydrophones)
		{
			Button btn = builder(new Button()).content(
				"F" ~ tabId.to!string ~ " " ~ ht.name ~ " BB").
				fontSize(BIG_BTN_FONT).build;
			hydrophoneTabs ~= btn;
			tabId++;
		}
		Button asonarTab = builder(new Button()).content("F" ~ tabId.to!string ~
			" Active sonar").fontSize(BIG_BTN_FONT).build;

		Button splitWindowTab = builder(new Button()).fontName("STIX2Math").content("⧉").
			fontSize(BIG_BTN_FONT).fixedSize(vec2i(BIG_BTN_FONT + 4, BIG_BTN_FONT)).build;

		splitWindowTab.onClick += {
			string cicAddr = Game.ciccon.url;
			spawnProcess(
				["./dsubs_client", "--coop", cicAddr],
				null, Config.detached | Config.suppressConsole);
		};

		tabs ~= [tacticalTab] ~ hydrophoneTabs ~ [asonarTab, splitWindowTab];

		int[] tabIdxToHotkeyKey;
		tabIdxToHotkeyKey.length = 8;
		static foreach (idx; 0 .. 8)
		{
			tabIdxToHotkeyKey[idx] = mixin("sfKeyF" ~ (idx + 1).to!string);
		}

		size_t tabFirstHtIdx = canAbandon ? 1 : 0;
		foreach (i, btn; tabs[tabFirstHtIdx .. $])
		{
			Game.hotkeyManager.setHotkey(Hotkey(tabIdxToHotkeyKey[i]),
				((btn) => { btn.simulateClick(); }) (btn));
		}

		Div tabDiv = builder(hDiv(cast(GuiElement[]) tabs)).fixedSize(vec2i(1, TAB_SIZE)).
			backgroundColor(COLORS.simPanelBgnd).mouseTransparent(false).build;

		// Course and speed labels

		curCourse = builder(new Label()).content("course: ").
			fontSize(BTN_FONT).htextAlign(HTextAlign.LEFT).build;
		curSpeed = builder(new Label()).content("speed: ").
			fontSize(BTN_FONT).htextAlign(HTextAlign.LEFT).build;

		// course and throttle setters

		Label tgtCourseLbl = builder(new Label()).content("tgt course (deg):").
			fontSize(BTN_FONT).htextAlign(HTextAlign.LEFT).build;
		Label tgtThrottleLbl = builder(new Label()).content("tgt throttle (%):").
			fontSize(BTN_FONT).htextAlign(HTextAlign.LEFT).build;

		static bool numericSymbFilter(dchar c)
		{
			if (c >= '0' && c <= '9' || c == '.' || c == '-')
				return true;
			return false;
		}

		tgtCourseField = builder(new TextField()).
			content(format("%.1f", -playerSub.targetCourse.compassAngle.rad2dgr)).
			symbolFilter(&numericSymbFilter).fontSize(BTN_FONT - 2).build;
		tgtThrottleField = builder(new TextField()).
			content(format("%.1f", 100.0f * playerSub.targetThrottle)).
			symbolFilter(&numericSymbFilter).fontSize(BTN_FONT - 2).build;

		m_mainHintLabel = builder(new Label()).
			fontSize(25).fontColor(sfColor(255, 255, 255, 50)).
			htextAlign(HTextAlign.CENTER).vtextAlign(VTextAlign.CENTER).
			content("SOME HINT").mouseTransparent(true).build();
		m_mainHintPanel = new Panel(m_mainHintLabel);

		void trySendTgtCourse()
		{
			try
			{
				float newTgt = tgtCourseField.content[0..$-1].to!float;
				if (isNaN(newTgt))
					throw new Exception("cheaky cunt, no NaNs");
				auto req = immutable CICCourseReq(-dgr2rad(newTgt));
				Game.ciccon.sendMessage(req);
			}
			catch (Exception e)
			{
				error(e.msg);
				tgtCourseField.content = "0";
			}
		}

		void trySendTgtThrottle()
		{
			try
			{
				float newTgt = tgtThrottleField.content[0..$-1].to!float;
				if (isNaN(newTgt))
					throw new Exception("cheaky cunt, no NaNs");
				if (newTgt > 100.0f)
				{
					tgtThrottleField.content = "100";
					newTgt = 100.0f;
				}
				if (newTgt < -100.0f)
				{
					tgtThrottleField.content = "-100";
					newTgt = -100.0f;
				}
				newTgt /= 100.0f;
				trace("setting throttle to: ", newTgt);
				Game.ciccon.sendMessage(immutable CICThrottleReq(newTgt));
				playerSub.targetThrottle = newTgt;
			}
			catch (Exception e)
			{
				error(e.msg);
				tgtThrottleField.content = "0";
			}
		}

		tgtCourseField.onKeyPressed += (evt)
		{
			if (evt.code == sfKeyReturn)
				trySendTgtCourse();
		};

		tgtThrottleField.onKeyPressed += (evt)
		{
			if (evt.code == sfKeyReturn)
				trySendTgtThrottle();
		};

		tgtCourseField.onKbFocusGain += ()
		{
			showMainHint(tgtCourseField, "Press ENTER to apply");
		};

		tgtThrottleField.onKbFocusGain += ()
		{
			showMainHint(tgtThrottleField, "Press ENTER to apply");
		};

		tgtCourseField.onKbFocusLoss += ()
		{
			hideMainHint(tgtCourseField);
		};

		tgtThrottleField.onKbFocusLoss += ()
		{
			hideMainHint(tgtThrottleField);
		};

		Game.hotkeyManager.setHotkey(Hotkey(sfKeyC), ()
		{
			tgtCourseField.requestKbFocus();
			tgtCourseField.selectAll();
		});
		Game.hotkeyManager.setHotkey(Hotkey(sfKeyT), ()
		{
			tgtThrottleField.requestKbFocus();
			tgtThrottleField.selectAll();
		});

		chatMessageBox = builder(new TextBox()).fontSize(MSG_FONT).
			fontColor(COLORS.simMessageFont).layoutType(LayoutType.GREEDY).build;

		GuiElement[] bottomDivEls = [
				builder(
						vDiv([curCourse, curSpeed])
					).fixedSize(vec2i(150, 1)).build,
				builder(
						vDiv([tgtCourseLbl, tgtThrottleLbl])
					).fixedSize(vec2i(180, 1)).build,
				builder(
						vDiv([tgtCourseField, tgtThrottleField])
					).fixedSize(vec2i(65, 1)).build,
				filler(20),
				chatMessageBox
			];
		if (canPause)
		{
			short currentAccel = Game.simState.timeAccelerationFactor;

			Button[] timeAccelerationButtons;
			timeAccelerationButtons ~= builder(new Button()).fontSize(15).
				content("x1 normal").build();
			timeAccelerationButtons[$-1].onClick += () {
				Game.ciccon.sendMessage(immutable CICTimeAccelerationReq(
					TimeAccelerationReq(10)));
			};
			timeAccelerationButtons ~= builder(new Button()).fontSize(15).
				content("x2 speed").build();
			timeAccelerationButtons[$-1].onClick += () {
				Game.ciccon.sendMessage(immutable CICTimeAccelerationReq(
					TimeAccelerationReq(20)));
			};
			timeAccelerationButtons ~= builder(new Button()).fontSize(15).
				content("x4 speed").build();
			timeAccelerationButtons[$-1].onClick += () {
				Game.ciccon.sendMessage(immutable CICTimeAccelerationReq(
					TimeAccelerationReq(40)));
			};
			timeAccelerationButtons ~= builder(new Button()).fontSize(15).
				content("x8 speed").build();
			timeAccelerationButtons[$-1].onClick += () {
				Game.ciccon.sendMessage(immutable CICTimeAccelerationReq(
					TimeAccelerationReq(80)));
			};
			timeAccelerationButtons ~= builder(new Button()).fontSize(15).
				content("x0.5 half").build();
			timeAccelerationButtons[$-1].onClick += () {
				Game.ciccon.sendMessage(immutable CICTimeAccelerationReq(
					TimeAccelerationReq(5)));
			};

			m_timeAccelBtn = builder(new Button()).
				content(timeAccelBtnContent(currentAccel)).fontSize(BTN_FONT).
				fixedSize(vec2i(BTN_FONT + 20, BIG_BTN_FONT)).build;
			m_timeAccelBtn.onClick += () {
				ContextMenu menu = contextMenu(
					Game.guiManager,
					timeAccelerationButtons,
					Game.window.size,
					vec2i(m_timeAccelBtn.position.x, m_timeAccelBtn.position.y),
					20);
			};
			bottomDivEls ~= m_timeAccelBtn;

			bool pausedNow = Game.simState.isPaused;
			m_pauseBtn = builder(new Button(ButtonType.ASYNC)).
				fontName("SansMono").
				content(pauseBtnContent(pausedNow)).fontSize(BIG_BTN_FONT).
				fixedSize(vec2i(BIG_BTN_FONT + 4, BIG_BTN_FONT)).build;
			m_pauseBtn.onClick += () {
				bool curPauseState = Game.simState.isPaused;
				Game.ciccon.sendMessage(immutable CICPauseSimulatorReq(
					PauseSimulatorReq(!curPauseState)));
			};
			bottomDivEls ~= m_pauseBtn;
		}
		Div bottomDiv = builder(hDiv(bottomDivEls)).
			fixedSize(vec2i(1, (BTN_FONT + 6) * 2)).
			backgroundColor(COLORS.simPanelBgnd).mouseTransparent(false).build;

		Div[] tubeUiDivs;
		foreach (Tube tube; playerSub.tubeRange.array.sort!("a.id < b.id"))
		{
			TubeUI ui = new TubeUI(tube);
			tubeUis[tube.id] = ui;
			tubeUiDivs ~= ui.mainDiv;
		}

		foreach (i, ht; playerSub.tmpl.hydrophones.filter!(
			ht => ht.type == HydrophoneType.towed).enumerate)
		{
			m_wireUis ~= new WireUi(i.to!int, "towed array " ~ (i + 1).to!string,
				ht.maxWireLength);
		}
		Div wireVertDiv = builder(vDiv([filler()] ~ cast(GuiElement[])
			m_wireUis.map!(wire => wire.rootDiv).array)).
			borderWidth(4).fixedSize(vec2i(200, 230)).build;

		auto goals = Game.simState.m_recState.rawState.goals;
		GuiElement goalsHdivEl;
		if (goals)
		{
			m_objectivesVdiv = builder(vDiv([buildGoalListDiv(goals), filler()])).
				fixedSize(vec2i(240, 50)).build;
			goalsHdivEl = builder(hDiv([m_objectivesVdiv, filler()])).build;
		}
		else
			goalsHdivEl = filler();

		GuiElement middleMainDiv = builder(vDiv([
			filler(20),
			goalsHdivEl,
			builder(hDiv(cast(GuiElement[]) tubeUiDivs ~ wireVertDiv)).
				fixedSize(vec2i(100, 260)).
				borderWidth(8).build
		])).build;

		bool[Div] passiveSonarDivs;
		foreach (i, hydroTmpl; playerSub.tmpl.hydrophones)
		{
			m_passiveGuis ~= createWaterfallPanel(hydroTmpl, i.to!int);
			passiveSonarDivs[m_passiveGuis[$-1].root] = true;
		}
		// synchronize waterfall cameras
		for (int i = 1; i < m_passiveGuis.length; i++)
			m_passiveGuis[i].wf.camera = m_passiveGuis[0].wf.camera;
		m_sonarGui = createSonarGui(playerSub.tmpl.sonar);

		m_topLevelDiv = builder(vDiv([
			tabDiv,
			middleMainDiv,
			bottomDiv
		])).build;

		void setMiddlePane(GuiElement el)
		{
			m_topLevelDiv.setChild(el, 1);
			if (el is middleMainDiv)
				Game.simState.tacticalOverlay.hidden = false;
			else
				Game.simState.tacticalOverlay.hidden = true;
			Game.inputRouter.clearFocused();
		}

		tacticalTab.onClick += ()
		{
			Game.simState.activeSonarSound = null;
			setMiddlePane(middleMainDiv);
		};
		foreach (i, btn; hydrophoneTabs)
		{
			btn.onClick += ((i) => {
				Game.simState.activeSonarSound = Game.simState.sonarSounds[i];
				setMiddlePane(m_passiveGuis[i].root);
				m_passiveGuis[i].wf.onShowRebuildFromCamera();
			})(i);
		}
		asonarTab.onClick += ()
		{
			Game.simState.activeSonarSound = null;
			setMiddlePane(m_sonarGui.root);
		};

		Game.guiManager.addPanel(new Panel(m_topLevelDiv));
	}
}
