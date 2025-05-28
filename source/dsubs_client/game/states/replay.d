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
module dsubs_client.game.states.replay;

import std.algorithm: min;
import std.datetime;
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
	enum int SIM_ID_FONT = 16;
}


final class ReplayState: GameState
{
	private
	{
		Date m_day;
		ReplaySlice[] m_slices;
		CameraController m_camController;
		ReplayOverlay m_overlay;
		ContactOverlayShapeCahe m_shapeCache;
		Slider m_timeSlider;
		TextField m_simIdBox;
		Label m_curTimeLabel;
		size_t m_curSlice = 0;
	}

	__gshared static string s_currentSimId = "main_arena";

	this(Date day, ReplaySlice[] slices)
	{
		m_day = day;
		m_slices = slices;
		m_shapeCache = new ContactOverlayShapeCahe();
	}

	override void setup()
	{
		trace("got ", m_slices.length, " replay slices for date: ", m_day);
		// set up camera
		if (m_slices)
			Game.worldManager.camCtx.camera.center = cast(vec2d) m_slices[0].objects[0].position;
		Game.worldManager.camCtx.camera.zoom = 0.01;
		m_camController = new CameraController(Game.worldManager.camCtx.camera);
		m_overlay = new ReplayOverlay(m_camController);
		Game.guiManager.addPanel(new Panel(m_overlay));
		m_timeSlider = new Slider();
		m_timeSlider.value = 0.0f;
		m_timeSlider.fixedSize = vec2i(10, 40);
		m_timeSlider.backgroundColor = COLORS.simPanelBgnd;
		m_timeSlider.handleLength = 15;
		m_timeSlider.handleWidth = 40;

		static bool numericSymbFilter(dchar c)
		{
			if (c >= '0' && c <= '9' || c == '-')
				return true;
			return false;
		}

		m_curTimeLabel = builder(new Label()).fixedSize(vec2i(220, 10)).fontSize(BTN_FONT - 5).build;

		m_timeSlider.wheelGain = 1.0f / m_slices.length;
		m_timeSlider.onValueChanged += (float newVal)
		{
			if (m_slices.length == 0)
				return;
			size_t newSlice = (floor(newVal * m_slices.length)).to!size_t;
			newSlice = min(newSlice, m_slices.length - 1);
			if (newSlice != m_curSlice)
			{
				m_curSlice = newSlice;
				m_overlay.rebuildFromSlice(m_slices[m_curSlice]);
				m_curTimeLabel.content = SysTime.fromUnixTime(m_slices[m_curSlice].unixTime, UTC()).to!string;
			}
		};

		void delegate(long, Modifier) hotkeyHandler =
			(long usecsDelta, Modifier curMods) {
				enum float KB_TIME_SPEED = 8.0f;
				float timeDeltaTracker = 0.0f;
				if (m_slices.length == 0)
					return;
				if (sfKeyboard_isKeyPressed(sfKeyA))
					timeDeltaTracker -= usecsDelta * 1e-6 * KB_TIME_SPEED;
				if (sfKeyboard_isKeyPressed(sfKeyD))
					timeDeltaTracker += usecsDelta * 1e-6 * KB_TIME_SPEED;
				if (timeDeltaTracker != 0.0f)
				{
					timeDeltaTracker /= m_slices.length;
					m_timeSlider.value = fmax(0.0f, fmin(1.0f,
						m_timeSlider.value + timeDeltaTracker));
				}
			};
		Game.hotkeyManager.addHoldkey(hotkeyHandler);

		TextField dateField = builder(new TextField()).content(
			m_day.toISOExtString()).symbolFilter(&numericSymbFilter).
			fixedSize(vec2i(170, 10)).fontSize(BTN_FONT).build;
		Button changeDateBtn = builder(new Button(ButtonType.ASYNC)).content("load day").
			fontSize(BTN_FONT).fixedSize(vec2i(150, 10)).build;

		changeDateBtn.onClick += ()
		{
			try
			{
				s_currentSimId = m_simIdBox.content.str;
				Game.bconm.con.sendMessage(immutable ReplayGetDataReq(s_currentSimId,
					Date.fromISOExtString(dateField.content.str).toISOExtString()));
			}
			catch (Exception ex)
			{
				error(ex.msg);
				changeDateBtn.signalClickEnd();
			}
		};

		Label simIdLabel = builder(new Label()).content("simulator_id:").
			fontSize(SIM_ID_FONT).fixedSize(vec2i(110, 10)).build;
		m_simIdBox = builder(new TextField()).content(s_currentSimId).
			fontSize(SIM_ID_FONT).fixedSize(vec2i(180, 10)).build;

		Div mainDiv = vDiv([
			builder(hDiv([dateField, changeDateBtn, simIdLabel, m_simIdBox, filler(), m_curTimeLabel])).fixedSize(
				vec2i(10, BTN_FONT + 5)).backgroundColor(COLORS.simPanelBgnd).build,
			filler(),
			m_timeSlider]);
		Game.guiManager.addPanel(new Panel(mainDiv));
		if (m_slices)
			m_overlay.rebuildFromSlice(m_slices[0]);
	}

	override void handleBackendDisconnect()
	{
		Game.activeState = new LoginScreenState();
	}

	override void handleCICDisconnect()
	{
		Game.activeState = new LoginScreenState();
	}
}


final class ReplayOverlayEl: OverlayElement
{
	private
	{
		CircleShape m_shape;
		LineShape m_velLine;
		Label m_prototypeLabel;
		Label m_nameLabel;
		ReplayObjectRecord m_record;
	}

	this(Overlay owner, ReplayObjectRecord record)
	{
		super(owner);
		mouseTransparent = true;
		m_record = record;
		final switch (record.type)
		{
			case ReplayObjectType.unknown:
				m_shape = Game.replayState.m_shapeCache.forContactTypeNew(ContactType.unknown);
				break;
			case ReplayObjectType.submarine:
				m_shape = Game.replayState.m_shapeCache.forContactTypeNew(ContactType.submarine);
				break;
			case ReplayObjectType.weapon:
				m_shape = Game.replayState.m_shapeCache.forContactTypeNew(ContactType.weapon);
				break;
			case ReplayObjectType.decoy:
				m_shape = Game.replayState.m_shapeCache.forContactTypeNew(ContactType.decoy);
				break;
			case ReplayObjectType.animal:
				m_shape = Game.replayState.m_shapeCache.forContactTypeNew(ContactType.environment);
				break;
		}
		if (m_record.dead)
			m_shape.borderColor = sfColor(100, 100, 100, 255);
		m_velLine = new LineShape(vec2d(5.0f, 5.0f), vec2d(6.0f, 5.0f), m_shape.borderColor, 2.0f);

		m_prototypeLabel = builder(new Label()).fontSize(12).fontColor(sfColor(200, 200, 200, 150)).
			enableScissorTest(false).htextAlign(HTextAlign.CENTER).vtextAlign(VTextAlign.CENTER).
			mouseTransparent(true).build();
		m_nameLabel = builder(new Label()).fontSize(14).fontColor(sfWhite).
			enableScissorTest(false).htextAlign(HTextAlign.CENTER).vtextAlign(VTextAlign.CENTER).
			mouseTransparent(true).build();

		m_prototypeLabel.content = m_record.prototype;
		m_prototypeLabel.size = cast(vec2i) vec2f(m_prototypeLabel.contentWidth + 10,
				m_prototypeLabel.contentHeight + 2);
		m_nameLabel.content = m_record.name;
		m_nameLabel.size = cast(vec2i) vec2f(m_nameLabel.contentWidth + 10,
				m_nameLabel.contentHeight + 2);
		size = cast(vec2i) vec2f(2 * m_shape.radius + 8, 2 * m_shape.radius + 8);
	}

	override void onPreDraw()
	{
		vec2d worldPos = cast(vec2d) m_record.position;
		vec2d screenPos = owner.world2screenPos(worldPos);
		assert(!isNaN(screenPos.x));
		assert(!isNaN(screenPos.y));
		vec2f screenPosF = cast(vec2f) screenPos;
		position = center2lu(screenPos);
		m_shape.center = screenPosF;
		vec2d velYInv = cast(vec2d) m_record.velocity;
		velYInv.y = - velYInv.y;
		m_velLine.setPoints(screenPos, screenPos + velYInv, true);
		m_prototypeLabel.position = vec2i(position.x + size.x / 2 - m_prototypeLabel.size.x / 2,
			position.y + size.y - 1);
		m_nameLabel.position = vec2i(position.x + size.x / 2 - m_nameLabel.size.x / 2,
			position.y + size.y + m_prototypeLabel.size.y - 1);
	}

	override void draw(Window wnd, long usecsDelta)
	{
		super.draw(wnd, usecsDelta);
		m_shape.render(wnd);
		m_velLine.render(wnd);
		m_prototypeLabel.draw(wnd, usecsDelta);
		m_nameLabel.draw(wnd, usecsDelta);
	}
}


final class ReplayOverlay: Overlay
{
	private
	{
		CameraController m_camCtrl;
		int m_mousePrevX, m_mousePrevY;
	}

	this(CameraController camCtrl)
	{
		m_camCtrl = camCtrl;
		mouseTransparent = false;
		// mouse and keyboard handlers
		onMouseDown += &processMouseDown;
		onMouseUp += &processMouseUp;
		onMouseMove += &processMouseMove;
		onMouseScroll += &processMouseScroll;
	}

	void rebuildFromSlice(ReplaySlice slice)
	{
		this.clear();
		foreach (ReplayObjectRecord record; slice.objects)
			this.add(new ReplayOverlayEl(this, record));
	}

	private void processMouseDown(int x, int y, sfMouseButton btn)
	{
		if (btn == sfMouseRight)
		{
			onPanStart(x, y);
			requestMouseFocus();
		}
	}

	private void processMouseUp(int x, int y, sfMouseButton btn)
	{
		if (btn == sfMouseRight)
			returnMouseFocus();
	}

	override void onPanStart(int x, int y)
	{
		m_mousePrevX = x;
		m_mousePrevY = y;
	}

	private void processMouseMove(int x, int y)
	{
		if (mouseFocused)
			onPan(x, y);
	}

	override void onPan(int x, int y)
	{
		m_camCtrl.onPan(x - m_mousePrevX, y - m_mousePrevY);
		m_mousePrevX = x;
		m_mousePrevY = y;
	}

	private void processMouseScroll(int x, int y, float delta)
	{
		m_camCtrl.onScroll(x, y, delta);
	}

	override vec2d world2screenPos(vec2d world)
	{
		return m_camCtrl.camera.transform2screen(world);
	}

	override double world2screenRot(double world)
	{
		return world - m_camCtrl.camera.rotation;
	}

	override vec2d screen2worldPos(vec2d screen)
	{
		return m_camCtrl.camera.transform2world(screen);
	}

	override double screen2worldRot(double screen)
	{
		return screen + m_camCtrl.camera.rotation;
	}

	override double world2screenLength(double world)
	{
		return world * m_camCtrl.camera.zoom;
	}

	override double screen2worldLength(double screen)
	{
		return screen / m_camCtrl.camera.zoom;
	}
}