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
module dsubs_client.game.tubeui;

import std.algorithm: map, canFind, filter;
import std.algorithm.comparison: min, max;
import std.array: array;
import std.format;

import core.time: MonoTime;

import derelict.sfml2.graphics;
import derelict.sfml2.system;

import dsubs_common.api.entities;
import dsubs_common.api.messages;
import dsubs_common.math;

import dsubs_client.common;
import dsubs_client.gui;
import dsubs_client.render.camera;
import dsubs_client.core.window;
import dsubs_client.game;
import dsubs_client.game.cic.messages;
import dsubs_client.game.entities;
import dsubs_client.game.tacoverlay;



private
{
	enum int FONT = 12;
	enum int LAUNCH_FONT = 15;
	enum int AIM_BLOCK_HEIGHT = 120;
}


final class TubeUI
{
	enum TubeUIAimState
	{
		notAiming,
		aiming,
		wireGuiding
	}

	private
	{
		Tube m_tube;
		Div m_mainDiv;

		// div that contains aiming weapon parameters
		Div m_aimDiv;
		// div that contains wire-guidance weapon parameters
		Div m_wireGuideDiv;
		// set of delegates that are run when certain gui element
		// must be update from the wire-guided weapon state
		void delegate()[WeaponParamType] m_wireParamUpdaters;
		// filler that takes it's place when the tube is neither
		// loaded nor wire-guiding
		GuiElement m_aimFiller;
		TubeUIAimState m_state;
		WeaponProjectionTrace m_overlayTrace;
		WeaponAimHandle m_overlayHandle;

		// main section
		GuiElement m_aimElement;
		Button m_aimButton;
		Button[TubeState.open + 1] m_desiredStateButtons;
		Button m_launchButton;
		Label m_currentStateLabel;
		Button m_weaponButton;
		Label m_tubeNameLabel;

		// weapon type that is consistent with aim controls and trails
		string m_aimingSectionWeapon;
		string m_wireGuidedWeapon;
		string m_wireGuidanceId;
	}

	@property Div mainDiv() { return m_mainDiv; }

	this(Tube tube)
	{
		m_tube = tube;

		m_tubeNameLabel = builder(new Label()).content("tube " ~ (m_tube.id + 1).to!string).
			fontSize(FONT).build;
		m_weaponButton = builder(new Button()).fontSize(FONT).build;
		m_currentStateLabel = builder(new Label()).fontSize(FONT).build;
		if (m_tube.tubeType == TubeType.standard)
		{
			m_aimButton = builder(new Button()).content("Aim").
				fontSize(FONT).backgroundColor(COLORS.simButtonBgnd).build;
			m_aimButton.onClick += &onAimButtonClick;
			m_aimElement = m_aimButton;
		}
		else
			m_aimElement = filler();
		m_launchButton = builder(new Button()).content("Launch").
			fontColor(COLORS.simButtonDisabledFont).fontSize(LAUNCH_FONT).
			backgroundColor(COLORS.simButtonDisabledBgnd).build;
		m_desiredStateButtons[TubeState.dry] =
			builder(new Button()).content("D").
				fontSize(LAUNCH_FONT).backgroundColor(COLORS.simButtonBgnd).build;
		m_desiredStateButtons[TubeState.flooded] =
			builder(new Button()).content("F").
				fontSize(LAUNCH_FONT).backgroundColor(COLORS.simButtonBgnd).build;
		m_desiredStateButtons[TubeState.open] =
			builder(new Button()).content("O").
				fontSize(LAUNCH_FONT).backgroundColor(COLORS.simButtonBgnd).build;

		Div desiredStateDiv = builder(hDiv(cast(GuiElement[]) m_desiredStateButtons[])).
			fixedSize(vec2i(100, LAUNCH_FONT + 4)).borderWidth(4).build;

		m_aimFiller = filler(AIM_BLOCK_HEIGHT);

		m_mainDiv = builder(vDiv([
			m_aimFiller,
			m_tubeNameLabel,
			m_aimElement,
			m_launchButton,
			desiredStateDiv,
			m_currentStateLabel,
			m_weaponButton])).borderWidth(4).fixedSize(vec2i(90, AIM_BLOCK_HEIGHT + 95)).build;

		// now we bind updates
		m_tube.onStateUpdate += &updateFromTube;
		m_launchButton.onClick += &m_tube.sendLaunchRequest;
		m_weaponButton.onClick += &createSelectWeaponContextMenu;
		for (TubeState state = TubeState.dry; state <= TubeState.open; state++)
		{
			Button btn = m_desiredStateButtons[state];
			btn.onClick += (newState) {
				return () { m_tube.sendDesiredStateRequest(newState); };
			} (state);
		}
	}

	void updateFromTube(Tube t)
	{
		assert(t is m_tube);
		updateWeaponContent();
		// update state label
		m_currentStateLabel.content = m_tube.currentState.to!string;
		updateDesiredStateButtons();
		updateLaunchButton();
	}

	private void dropTraceAndHandle()
	{
		if (m_overlayTrace)
		{
			Game.simState.tacticalOverlay.remove(m_overlayTrace);
			m_overlayTrace = null;
		}
		if (m_overlayHandle)
		{
			Game.simState.tacticalOverlay.remove(m_overlayHandle);
			m_overlayHandle = null;
		}
	}

	private void recreateAim()
	{
		m_aimingSectionWeapon = m_tube.loadedWeapon;
		buildAimDiv();
		m_mainDiv.setChild(m_aimDiv, 0);
		// build trace overlay
		m_overlayTrace = new WeaponProjectionTrace(
			Game.simState.tacticalOverlay, m_tube);
		m_overlayHandle = new WeaponAimHandle(
			Game.simState.tacticalOverlay, m_tube, this);
	}

	void recreateWireGuidance(WireGuidedWeapon wgw)
	{
		m_wireGuidedWeapon = wgw.tube.wireGuidedWeaponName;
		assert(m_wireGuidedWeapon);
		m_wireGuidanceId = wgw.wireGuidanceId;
		buildWireGuidanceDiv(wgw);
		m_mainDiv.setChild(m_wireGuideDiv, 0);
		m_state = TubeUIAimState.wireGuiding;
	}

	void cutWireGuidance()
	{
		if (m_state == TubeUIAimState.wireGuiding)
		{
			m_mainDiv.setChild(m_aimFiller, 0);
			m_wireParamUpdaters.clear();
			m_state = TubeUIAimState.notAiming;
		}
	}

	// called when CIC re-broadcasts WireGuidanceUpdateParamsReq
	void updateWireGuidanceParamFromWeapon(WeaponParamType type)
	{
		if (type in m_wireParamUpdaters)
			m_wireParamUpdaters[type]();
	}

	private void onAimButtonClick()
	{
		if (m_state == TubeUIAimState.notAiming && m_tube.loadedWeapon)
		{
			recreateAim();
			m_aimButton.content = "Stop aiming";
			m_state = TubeUIAimState.aiming;
		}
		else
		{
			m_aimButton.content = "Aim";
			m_mainDiv.setChild(m_aimFiller, 0);
			dropTraceAndHandle();
			m_state = TubeUIAimState.notAiming;
		}
	}

	private
	{
		TextField m_courseTextField;
		TextField m_activationRangeField;
	}

	void updateAimFieldsFromTube()
	{
		string marchCourseContent;
		WeaponParamValue* wpv = WeaponParamType.course in m_tube.weaponParams;
		if (wpv)
			marchCourseContent = format("%.1f", -wpv.course.compassAngle.rad2dgr);
		m_courseTextField.content = marchCourseContent;
		string activationRangeContent = format("%.0f",
			m_tube.weaponParams[WeaponParamType.activationRange].range);
		if (m_activationRangeField)
			m_activationRangeField.content = activationRangeContent;
	}

	private void buildAimDiv()
	{
		// build m_aimDiv
		Label courseLabel = builder(new Label()).content("course ").
			fontSize(FONT).fixedSize(vec2i(45, 1)).build;
		m_courseTextField = builder(new TextField()).symbolFilter(&numericSymbFilter).
			fontSize(FONT).build;
		m_courseTextField.onKeyReleased += (k) {
			if (m_courseTextField.content.length == 1)
			{
				m_tube.weaponParams.remove(WeaponParamType.course);
			}
			else
			{
				try
				{
					float newTgt = m_courseTextField.content[0..$-1].to!float;
					if (!isNaN(newTgt))
					{
						float radTgt = -newTgt.dgr2rad;
						m_tube.course = radTgt;
					}
				}
				catch (Exception e) {}
			}
		};

		Label activationRangeLabel;
		if (m_tube.activationRangeLimits.min < m_tube.activationRangeLimits.max)
		{
			activationRangeLabel = builder(new Label()).content("RTE(m) ").
				fontSize(FONT).fixedSize(vec2i(45, 1)).build;
			m_activationRangeField = builder(new TextField()).
				symbolFilter(&numericSymbFilter).fontSize(FONT).build;
			m_activationRangeField.onKeyReleased += (k) {
				try
				{
					float rawTgt = m_activationRangeField.content[0..$-1].to!float;
					if (!isNaN(rawTgt))
					{
						float clampedTgt = max(m_tube.activationRangeLimits.min, rawTgt);
						clampedTgt = min(m_tube.activationRangeLimits.max, clampedTgt);
						m_tube.activationRange = clampedTgt;
						if (rawTgt < clampedTgt && rawTgt >= 0.0f)
							m_activationRangeField.content = format("%.0f", rawTgt);
						else
							m_activationRangeField.content = format("%.0f", clampedTgt);
					}
				}
				catch (Exception e) {}
			};
			m_activationRangeField.onKbFocusLoss += ()
			{
				m_activationRangeField.content = format("%.0f",
					m_tube.weaponParams[WeaponParamType.activationRange].range);
			};
		}
		else
			m_activationRangeField = null;

		Label marchSpeedLabel;
		TextField marchSpeedField;
		if (m_tube.marchSpeedLimits.min < m_tube.marchSpeedLimits.max)
		{
			marchSpeedLabel = builder(new Label()).content("RTE spd ").
				fontSize(FONT).fixedSize(vec2i(50, 1)).build;
			string marchSpeedContent = format("%.1f",
				m_tube.weaponParams[WeaponParamType.marchSpeed].speed);
			marchSpeedField = builder(new TextField()).
				symbolFilter(&numericSymbFilter).content(marchSpeedContent).
				fontSize(FONT).build;
			marchSpeedField.onKeyReleased += (k) {
				try
				{
					float rawTgt = marchSpeedField.content[0..$-1].to!float;
					if (!isNaN(rawTgt))
					{
						float clampedTgt = max(m_tube.marchSpeedLimits.min, rawTgt);
						clampedTgt = min(m_tube.marchSpeedLimits.max, clampedTgt);
						m_tube.marchSpeed = clampedTgt;
						if (rawTgt < clampedTgt && rawTgt >= 0.0f)
							marchSpeedField.content = format("%.1f", rawTgt);
						else
							marchSpeedField.content = format("%.1f", clampedTgt);
					}
				}
				catch (Exception e) {}
			};
			marchSpeedField.onKbFocusLoss += ()
			{
				marchSpeedField.content = format("%.1f",
					m_tube.weaponParams[WeaponParamType.marchSpeed].speed);
			};
		}

		Label activeSpeedLabel;
		TextField activeSpeedField;
		if (m_tube.activeSpeedLimits.min < m_tube.activeSpeedLimits.max)
		{
			activeSpeedLabel = builder(new Label()).content("ACT spd ").
				fontSize(FONT).fixedSize(vec2i(50, 1)).build;
			string activeSpeedContent = format("%.1f",
				m_tube.weaponParams[WeaponParamType.activeSpeed].speed);
			activeSpeedField = builder(new TextField()).
				symbolFilter(&numericSymbFilter).content(activeSpeedContent).
				fontSize(FONT).build;
			activeSpeedField.onKeyReleased += (k) {
				try
				{
					float rawTgt = activeSpeedField.content[0..$-1].to!float;
					if (!isNaN(rawTgt))
					{
						float clampedTgt = max(m_tube.activeSpeedLimits.min, rawTgt);
						clampedTgt = min(m_tube.activeSpeedLimits.max, clampedTgt);
						m_tube.activeSpeed = clampedTgt;
						if (rawTgt < clampedTgt && rawTgt >= 0.0f)
							activeSpeedField.content = format("%.1f", rawTgt);
						else
							activeSpeedField.content = format("%.1f", clampedTgt);
					}
				}
				catch (Exception e) {}
			};
			activeSpeedField.onKbFocusLoss += ()
			{
				activeSpeedField.content = format("%.1f",
					m_tube.weaponParams[WeaponParamType.activeSpeed].speed);
			};
		}

		Label patternLabel;
		Button patternButton;
		if (m_tube.availableSearchPatterns.length > 1)
		{
			patternLabel = builder(new Label()).content("ptrn ").
				fontSize(FONT).fixedSize(vec2i(30, 1)).build;
			patternButton = builder(new Button()).content(
				m_tube.weaponParams[WeaponParamType.searchPattern].searchPattern.to!string).
				fontSize(FONT).backgroundColor(COLORS.simButtonBgnd).build;
			patternButton.onClick += () {
				Button[] spButtons;
				foreach (WeaponSearchPattern pattern; m_tube.availableSearchPatterns)
				{
					Button btn = builder(new Button()).content(pattern.to!string).
						fontSize(FONT).build;
					btn.onClick += (WeaponSearchPattern p) {
						return {
							// we may be way too late and the weapon was changed, so we check
							if (m_tube.availableSearchPatterns.canFind(p))
							{
								m_tube.searchPattern = p;
								patternButton.content = p.to!string;
							}
						};
					} (pattern);
					spButtons ~= btn;
				}
				contextMenu(Game.guiManager, spButtons, Game.window.size,
					Game.window.mousePos, FONT + 4);
			};
		}

		Label sensorLabel;
		Button sensorButton;
		if (m_tube.availableSensorModes.length > 1)
		{
			sensorLabel = builder(new Label()).content("sens ").
				fontSize(FONT).fixedSize(vec2i(30, 1)).build;
			sensorButton = builder(new Button()).content(
				m_tube.sensorMode.to!string).
				fontSize(FONT).backgroundColor(COLORS.simButtonBgnd).build;
			sensorButton.onClick += () {
				Button[] smButtons;
				foreach (WeaponSensorMode sensMode; m_tube.availableSensorModes)
				{
					Button btn = builder(new Button()).content(sensMode.to!string).
						fontSize(FONT).build;
					btn.onClick += (WeaponSensorMode sm) {
						return {
							// we may be way too late and the weapon was changed, so we check
							if (m_tube.availableSensorModes.canFind(sm))
							{
								m_tube.sensorMode = sm;
								sensorButton.content = sm.to!string;
							}
						};
					} (sensMode);
					smButtons ~= btn;
				}
				contextMenu(Game.guiManager, smButtons, Game.window.size,
					Game.window.mousePos, FONT + 4);
			};
		}

		m_aimDiv = builder(vDiv([
				filler(),
				builder(hDiv([courseLabel, m_courseTextField])).
					fixedSize(vec2i(1, FONT + 4)).build,
				m_activationRangeField ?
					builder(hDiv([activationRangeLabel, m_activationRangeField])).
						fixedSize(vec2i(1, FONT + 4)).build : null,
				marchSpeedLabel ?
					builder(hDiv([marchSpeedLabel, marchSpeedField])).
						fixedSize(vec2i(1, FONT + 4)).build : null,
				activeSpeedLabel ?
					builder(hDiv([activeSpeedLabel, activeSpeedField])).
						fixedSize(vec2i(1, FONT + 4)).build : null,
				patternLabel ?
					builder(hDiv([patternLabel, patternButton])).
						fixedSize(vec2i(1, FONT + 4)).build : null,
				sensorLabel ?
					builder(hDiv([sensorLabel, sensorButton])).
						fixedSize(vec2i(1, FONT + 4)).build : null
			].filter!(e => e !is null).array)).borderWidth(4).
				fixedSize(vec2i(80, AIM_BLOCK_HEIGHT)).build;

		// bind up and down keys in cycle
		TextField[] allTextFields;
		for (size_t i = 1; i < m_aimDiv.children.length; i++)
		{
			TextField curField = cast(TextField)(
				(cast(Div) m_aimDiv.children[i]).children[1]);
			if (curField !is null)
				allTextFields ~= curField;
		}
		for (size_t i = 0; i < allTextFields.length; i++)
		{
			TextField curField = allTextFields[i];
			TextField nextField = allTextFields[(i + 1) % $];
			curField.onKeyPressed += (nf) {
				return (const sfKeyEvent* evt) {
					if (evt.code == sfKeyDown)
						nf.requestKbFocus();
					};
				} (nextField);
			nextField.onKeyPressed += (cf) {
				return (const sfKeyEvent* evt) {
					if (evt.code == sfKeyUp)
						cf.requestKbFocus();
					};
				} (curField);
		}

		updateAimFieldsFromTube();
	}

	private void buildWireGuidanceDiv(WireGuidedWeapon wgw)
	{
		// build m_aimDiv
		Label courseLabel = builder(new Label()).content("course ").
			fontSize(FONT).fixedSize(vec2i(45, 1)).build;

		m_courseTextField = builder(new TextField()).
			symbolFilter(&numericSymbFilter).fontSize(FONT).build;
		m_wireParamUpdaters[WeaponParamType.course] = () {
			string courseFieldContent = format("%.1f",
				-wgw.weaponParams[WeaponParamType.course].course.compassAngle.rad2dgr);
			m_courseTextField.content = courseFieldContent;
		};
		m_wireParamUpdaters[WeaponParamType.course]();
		m_courseTextField.onKbFocusLoss += () {
			if (m_courseTextField.content.length > 1)
			{
				try
				{
					float newTgt = m_courseTextField.content[0..$-1].to!float;
					if (!isNaN(newTgt))
					{
						float radTgt = -newTgt.dgr2rad;
						WeaponParamValue courseParam = WeaponParamValue(
							WeaponParamType.course);
						courseParam.course = radTgt;
						wgw.sendDesiredParamValue(courseParam);
					}
				}
				catch (Exception e) {}
			}
		};

		// activation range is never controlled by wire
		m_activationRangeField = null;

		Label marchSpeedLabel;
		TextField marchSpeedField;
		if (WeaponParamType.marchSpeed in wgw.weaponParams)
		{
			marchSpeedLabel = builder(new Label()).content("RTE spd ").
				fontSize(FONT).fixedSize(vec2i(50, 1)).build;
			marchSpeedField = builder(new TextField()).
				symbolFilter(&numericSymbFilter).fontSize(FONT).build;
			m_wireParamUpdaters[WeaponParamType.marchSpeed] = () {
				string marchSpeedContent = format("%.1f",
					wgw.weaponParams[WeaponParamType.marchSpeed].speed);
				marchSpeedField.content = marchSpeedContent;
			};
			m_wireParamUpdaters[WeaponParamType.marchSpeed]();
			marchSpeedField.onKbFocusLoss += () {
				try
				{
					float rawTgt = marchSpeedField.content[0..$-1].to!float;
					if (!isNaN(rawTgt))
					{
						float clampedTgt = max(wgw.marchSpeedLimits.min, rawTgt);
						clampedTgt = min(wgw.marchSpeedLimits.max, clampedTgt);
						marchSpeedField.content = format("%.1f", clampedTgt);
						WeaponParamValue spdParam = WeaponParamValue(
							WeaponParamType.marchSpeed);
						spdParam.speed = clampedTgt;
						wgw.sendDesiredParamValue(spdParam);
					}
				}
				catch (Exception e)
				{
					marchSpeedField.content = format("%.1f",
						wgw.weaponParams[WeaponParamType.marchSpeed].speed);
				}
			};
		}

		Label activeSpeedLabel;
		TextField activeSpeedField;
		if (WeaponParamType.activeSpeed in wgw.weaponParams)
		{
			activeSpeedLabel = builder(new Label()).content("ACT spd ").
				fontSize(FONT).fixedSize(vec2i(50, 1)).build;
			activeSpeedField = builder(new TextField()).
				symbolFilter(&numericSymbFilter).fontSize(FONT).build;
			m_wireParamUpdaters[WeaponParamType.activeSpeed] = () {
				string activeSpeedContent = format("%.1f",
					wgw.weaponParams[WeaponParamType.activeSpeed].speed);
				activeSpeedField.content = activeSpeedContent;
			};
			m_wireParamUpdaters[WeaponParamType.activeSpeed]();
			activeSpeedField.onKbFocusLoss += () {
				try
				{
					float rawTgt = activeSpeedField.content[0..$-1].to!float;
					if (!isNaN(rawTgt))
					{
						float clampedTgt = max(wgw.activeSpeedLimits.min, rawTgt);
						clampedTgt = min(wgw.activeSpeedLimits.max, clampedTgt);
						activeSpeedField.content = format("%.1f", clampedTgt);
						WeaponParamValue spdParam = WeaponParamValue(
							WeaponParamType.activeSpeed);
						spdParam.speed = clampedTgt;
						wgw.sendDesiredParamValue(spdParam);
					}
				}
				catch (Exception e)
				{
					activeSpeedField.content = format("%.1f",
						wgw.weaponParams[WeaponParamType.activeSpeed].speed);
				}
			};
		}

		Label patternLabel;
		Button patternButton;
		if (WeaponParamType.searchPattern in wgw.weaponParams)
		{
			patternLabel = builder(new Label()).content("ptrn ").
				fontSize(FONT).fixedSize(vec2i(30, 1)).build;
			patternButton = builder(new Button()).
				fontSize(FONT).backgroundColor(COLORS.simButtonBgnd).build;
			m_wireParamUpdaters[WeaponParamType.searchPattern] = () {
				string ptrnContent =
					wgw.weaponParams[WeaponParamType.searchPattern].
						searchPattern.to!string;
				patternButton.content = ptrnContent;
			};
			m_wireParamUpdaters[WeaponParamType.searchPattern]();
			patternButton.onClick += () {
				Button[] spButtons;
				foreach (WeaponSearchPattern pattern; wgw.availableSearchPatterns)
				{
					Button btn = builder(new Button()).content(pattern.to!string).
						fontSize(FONT).build;
					btn.onClick += (WeaponSearchPattern p) {
						return {
							WeaponParamValue ptrnParam = WeaponParamValue(
								WeaponParamType.searchPattern);
							ptrnParam.searchPattern = p;
							wgw.sendDesiredParamValue(ptrnParam);
							patternButton.content = p.to!string;
						};
					} (pattern);
					spButtons ~= btn;
				}
				contextMenu(Game.guiManager, spButtons, Game.window.size,
					Game.window.mousePos, FONT + 4);
			};
		}

		Label sensorLabel;
		Button sensorButton;
		if (WeaponParamType.sensorMode in wgw.weaponParams)
		{
			sensorLabel = builder(new Label()).content("sens ").
				fontSize(FONT).fixedSize(vec2i(30, 1)).build;
			sensorButton = builder(new Button()).
				fontSize(FONT).backgroundColor(COLORS.simButtonBgnd).build;
			m_wireParamUpdaters[WeaponParamType.sensorMode] = () {
				string sensorContent =
					wgw.weaponParams[WeaponParamType.sensorMode].
						sensorMode.to!string;
				sensorButton.content = sensorContent;
			};
			m_wireParamUpdaters[WeaponParamType.sensorMode]();
			sensorButton.onClick += () {
				Button[] smButtons;
				foreach (WeaponSensorMode sensMode; wgw.availableSensorModes)
				{
					Button btn = builder(new Button()).content(sensMode.to!string).
						fontSize(FONT).build;
					btn.onClick += (WeaponSensorMode sm) {
						return {
							WeaponParamValue sensorParam = WeaponParamValue(
								WeaponParamType.sensorMode);
							sensorParam.sensorMode = sm;
							wgw.sendDesiredParamValue(sensorParam);
							sensorButton.content = sm.to!string;
						};
					} (sensMode);
					smButtons ~= btn;
				}
				contextMenu(Game.guiManager, smButtons, Game.window.size,
					Game.window.mousePos, FONT + 4);
			};
		}

		Button activateBtn, deactivateBtn;
		{
			activateBtn = builder(new Button()).content("Activ").
				fontSize(FONT).backgroundColor(COLORS.simButtonBgnd).build;
			activateBtn.onClick += () {
				wgw.sendShouldBeActive(true);
			};
			deactivateBtn = builder(new Button()).content("Deact").
				fontSize(FONT).backgroundColor(COLORS.simButtonBgnd).build;
			deactivateBtn.onClick += () {
				wgw.sendShouldBeActive(false);
			};
		}

		m_wireGuideDiv = builder(vDiv([
				filler(),
				builder(hDiv([activateBtn, deactivateBtn])).
					fixedSize(vec2i(1, FONT + 4)).build,
				builder(hDiv([courseLabel, m_courseTextField])).
					fixedSize(vec2i(1, FONT + 4)).build,
				marchSpeedLabel ?
					builder(hDiv([marchSpeedLabel, marchSpeedField])).
						fixedSize(vec2i(1, FONT + 4)).build : null,
				activeSpeedLabel ?
					builder(hDiv([activeSpeedLabel, activeSpeedField])).
						fixedSize(vec2i(1, FONT + 4)).build : null,
				patternLabel ?
					builder(hDiv([patternLabel, patternButton])).
						fixedSize(vec2i(1, FONT + 4)).build : null,
				sensorLabel ?
					builder(hDiv([sensorLabel, sensorButton])).
						fixedSize(vec2i(1, FONT + 4)).build : null
			].filter!(e => e !is null).array)).borderWidth(4).
				fixedSize(vec2i(80, AIM_BLOCK_HEIGHT)).build;

		// bind up and down keys in cycle
		TextField[] allTextFields;
		for (size_t i = 2; i < m_wireGuideDiv.children.length; i++)
		{
			TextField curField = cast(TextField)(
				(cast(Div) m_wireGuideDiv.children[i]).children[1]);
			if (curField !is null)
				allTextFields ~= curField;
		}
		for (size_t i = 0; i < allTextFields.length; i++)
		{
			TextField curField = allTextFields[i];
			TextField nextField = allTextFields[(i + 1) % $];
			curField.onKeyPressed += (nf) {
				return (const sfKeyEvent* evt) {
					if (evt.code == sfKeyDown)
						nf.requestKbFocus();
					};
				} (nextField);
			nextField.onKeyPressed += (cf) {
				return (const sfKeyEvent* evt) {
					if (evt.code == sfKeyUp)
						cf.requestKbFocus();
					};
				} (curField);
		}
	}

	private static bool numericSymbFilter(dchar c)
	{
		if (c >= '0' && c <= '9' || c == '.' || c == '-')
			return true;
		return false;
	}

	private void createSelectWeaponContextMenu()
	{
		Button chooseEmpty = builder(new Button()).
			content("empty").fontSize(FONT).build;
		chooseEmpty.onClick += { m_tube.sendDesiredWeaponRequest(null); };
		Button[] contextButtons = [chooseEmpty];
		foreach (weaponCountPair; m_tube.room.weaponCounts.byKeyValue)
		{
			if (weaponCountPair.value > 0)
			{
				string weaponName = weaponCountPair.key;
				Button loadWeaponBtn = builder(new Button()).
					content(weaponName ~ " x" ~ weaponCountPair.value.to!string).
					fontSize(FONT).build;
				loadWeaponBtn.onClick += (string wpnNameVal)
					{
						return { m_tube.sendDesiredWeaponRequest(wpnNameVal); };
					} (weaponName);
				contextButtons ~= loadWeaponBtn;
			}
		}
		contextMenu(Game.guiManager, contextButtons, Game.window.size,
			Game.window.mousePos, FONT + 4);
	}

	private void updateWeaponContent()
	{
		string currentWeaponName = m_tube.loadedWeapon;
		if (currentWeaponName == null)
			currentWeaponName = "empty";
		if (m_tube.currentState == TubeState.unloading)
		{
			string desiredWeaponName = m_tube.desiredWeapon;
			if (desiredWeaponName == null)
				desiredWeaponName = "empty";
			m_weaponButton.content = currentWeaponName[0..4] ~ "->" ~
				desiredWeaponName[0..4];
		}
		else
			m_weaponButton.content = currentWeaponName;
		if (m_tube.currentState == TubeState.dry ||
			m_tube.currentState == TubeState.unloading ||
			m_tube.currentState == TubeState.loading)
		{
			m_weaponButton.backgroundColor = COLORS.simButtonBgnd;
			m_weaponButton.pressable = true;
		}
		else
		{
			m_weaponButton.backgroundColor = sfTransparent;
			m_weaponButton.pressable = false;
		}
		// aim-button related stuff
		if (m_tube.loadedWeapon == null)
		{
			if (m_aimButton)
				m_aimButton.pressable = false;
			if (m_state == TubeUIAimState.aiming)
			{
				onAimButtonClick();
				assert(m_state == TubeUIAimState.notAiming);
			}
		}
		else
		{
			if (m_aimButton)
				m_aimButton.pressable = true;
			if (m_state == TubeUIAimState.aiming &&
				m_aimingSectionWeapon != m_tube.loadedWeapon)
			{
				// weapon was changed without toggling aim button, we need
				// to recreate aim section
				dropTraceAndHandle();
				recreateAim();
			}
		}
	}

	private void updateDesiredStateButtons()
	{
		for (TubeState state = TubeState.dry; state <= TubeState.open; state++)
		{
			Button btn = m_desiredStateButtons[state];
			if (state == m_tube.desiredState)
				btn.backgroundColor = COLORS.simButtonSelectedStateBgnd;
			else
				btn.backgroundColor = COLORS.simButtonBgnd;
			// we do not allow desired state switch during loading/unloading
			if (m_tube.currentState == TubeState.unloading ||
				m_tube.currentState == TubeState.loading)
				btn.pressable = false;
			else
				btn.pressable = true;
		}
	}

	private void updateLaunchButton()
	{
		if (m_tube.loadedWeapon != null && m_tube.currentState == TubeState.open)
		{
			m_launchButton.backgroundColor = COLORS.simLaunchButtonBgnd;
			m_launchButton.fontColor = sfBlack;
			m_launchButton.pressable = true;
		}
		else
		{
			m_launchButton.backgroundColor = COLORS.simButtonDisabledBgnd;
			m_launchButton.fontColor = COLORS.simButtonDisabledFont;
			m_launchButton.pressable = false;
		}
	}
}