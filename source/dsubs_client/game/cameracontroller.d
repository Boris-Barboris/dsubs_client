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
module dsubs_client.game.cameracontroller;

import std.math;

import std.experimental.logger;

import dsubs_common.math;

import dsubs_client.core.utils;
import dsubs_client.game;
import dsubs_client.gui;
import dsubs_client.input.router;
import dsubs_client.input.hotkeymanager;
import dsubs_client.render.camera;



/// Camera controller that handles panning and zooming on tactical overlay
final class CameraController
{
	float zoomTgtK = 0.25f;
	float kbPanSpeed = 1500.0f;
	float kbZoomSpeed = 4.0f;

	bool isMouseEventInteresting(Window wnd, const sfEvent* evt, int x, int y)
	{
		if (evt.type == sfEvtMouseButtonPressed && evt.mouseButton.button == sfMouseRight)
			return true;
		if (evt.type == sfEvtMouseWheelScrolled)
			return true;
		return false;
	}

	mixin Readonly!(Camera2D, "camera");

	/// register panning and zooming hotkeys
	this(Camera2D cam)
	{
		m_camera = cam;
		Game.hotkeyManager.addHoldkey(&handleKeyboard);
		Game.hotkeyManager.setHotkey(Hotkey(sfKeyEscape),
			&resetCameraToPlayerSub);
		Game.render.onPreRender += &handleSmooth;
	}

	private void resetCameraToPlayerSub()
	{
		m_camera.center = Game.simState.playerSub.transform.wposition;
	}

	private void handleKeyboard(long usecs, Modifier curMods)
	{
		if (curMods == Modifier.NONE)
		{
			// pan
			vec2d pan = vec2d(0.0, 0.0);
			if (sfKeyboard_isKeyPressed(sfKeyLeft))
				pan.x -= 1.0;
			if (sfKeyboard_isKeyPressed(sfKeyRight))
				pan.x += 1.0;
			if (sfKeyboard_isKeyPressed(sfKeyDown))
				pan.y -= 1.0;
			if (sfKeyboard_isKeyPressed(sfKeyUp))
				pan.y += 1.0;
			pan *= double(usecs) / 1e6 * kbPanSpeed;
			m_camera.pan(pan / m_camera.zoom);

			// zoom
			double dz = 0.0;
			if (sfKeyboard_isKeyPressed(sfKeyE))
				dz += 1.0;
			if (sfKeyboard_isKeyPressed(sfKeyQ))
				dz -= 1.0;
			dz *= double(usecs) / 1e6 * kbZoomSpeed;
			dz = fmax(-0.5, dz);
			m_camera.zoom = fmin(25.0, fmax(0.001, m_camera.zoom * (1.0 + dz)));
		}
	}

	void onPan(int dx, int dy)
	{
		vec2d panning = -vec2d(dx, -dy) / m_camera.zoom;
		m_camera.pan(panning);
	}

	void onScroll(int x, int y, float delta)
	{
		if (isNaN(targetZoom))
			targetZoom = m_camera.zoom;
		double oldZoom = targetZoom;
		double dzoom = oldZoom * zoomTgtK * delta;
		targetZoom = fmin(25.0, fmax(0.0025, targetZoom + dzoom));
		// point under cursor does not move on the screen during zoom
		double ux = x - m_camera.screenSize.x / 2.0;
		double uy = y - m_camera.screenSize.y / 2.0;
		zoomPivot = vec2d(ux, -uy);
		smoothing = true;
	}

	private
	{
		bool smoothing = false;
		double targetZoom;
		vec2d zoomPivot;
		double zoomVel = 0.0;
		double zoomAcc = 60.0;
	}

	private static double parabolicMove(double y1, double v1, double y2,
		double k, double dt, out double v3)
	{
		assert(k > 0.0);
		assert(dt > 0.0);
		double d = fabs(y2 - y1);
		double sign = sgn(y2 - y1);
		if (v1 * sign < 0.0)
			v1 = 0.0;
		v1 = fabs(v1);
		double t1 = v1 / 2 / k;
		assert(t1 >= 0.0);
		double cc = d - k * t1 * t1;
		if (cc <= 1e-10)
		{
			// descent on second parabola
			double tleft = t1 - dt;
			if (tleft <= 0.0)
			{
				v3 = 0.0;
				return y2;
			}
			v3 = sign * tleft * k * 2;
			return y2 - sign * k * tleft * tleft;
		}
		else
		{
			// ascent on first parabola
			double t2sqr = 2 * (d + k * t1 * t1) / k;
			double t2 = sqrt(t2sqr);
			if (t1 + dt >= t2)
			{
				v3 = 0.0;
				return y2;
			}
			double tres = t1 + dt;
			if (tres <= t2 / 2)
			{
				v3 = sign * 2 * k * tres;
				double y0 = y1 - sign * k * t1 * t1;
				return y0 + sign * k * tres * tres;
			}
			else
			{
				double tleft = t2 - tres;
				v3 = sign * 2 * k * tleft;
				return y2 - sign * k * tleft * tleft;
			}
		}
	}

	private void handleSmooth(long usecs)
	{
		if (!smoothing)
			return;
		double dt = double(usecs) / 1e6;
		// zooming
		double oldZoom = m_camera.zoom;
		double accK = targetZoom < oldZoom ? 1.6 : 1.0;
		m_camera.zoom = parabolicMove(oldZoom, zoomVel, targetZoom, accK * zoomAcc * oldZoom, dt, zoomVel);
		if (m_camera.zoom == targetZoom)
			smoothing = false;
		// panning while zooming
		vec2d topan = zoomPivot / oldZoom - zoomPivot / m_camera.zoom;
		if (zoomVel < 0)
			topan = 0.4 * topan;
		m_camera.pan(topan);
	}
}