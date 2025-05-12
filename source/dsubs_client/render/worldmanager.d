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
module dsubs_client.render.worldmanager;

import core.atomic;
import core.time;
import core.thread;
import core.sync.mutex;

import std.algorithm;
import std.experimental.logger;
import std.range;

import derelict.sfml2.graphics;

import dsubs_common.math;

import dsubs_client.core.window;
import dsubs_client.core.utils;
import dsubs_client.input.router;
import dsubs_client.math.transform;
import dsubs_client.render.render;
import dsubs_client.render.camera;


/// Something that is rendered in world space.
/// Reference frame hierarchies are implemented using transform parenting.
class WorldRenderable
{
	mixin Readonly!(Transform, "transform");

	this()
	{
		m_transform = new Transform();
	}

	/// Generally, it may well be some texture instead of a window
	abstract void render(Window wnd);

	/** View is not a model. Component transform is not bound to objects real
	(server-side) position and may be inter\extrapolated on arbitrary refresh rate.
	To create an illusion of smoothness, game objects will update their transforms
	every frame. After update, all renderables will be rendered by all interested
	cameras.
	Child classes should call super.update at the very end of their update overload. */
	void update(CameraContext camCtx, long usecsDelta) {}
}

/// Wrapper around camera
final class CameraContext
{
	Camera2D camera;

	// TODO: here is the place for some spacial optimization structures that are
	// related to the camera itself

	// window or any other renderable
	this(scope Window wnd)
	{
		camera = new Camera2D(vec2ui(wnd.width, wnd.height));
	}
}


/// Something that may receive mouse events in the context of world space
interface IWorldMouseReceiver: IInputReceiver
{
	bool isMouseEventInteresting(Window wnd, const sfEvent* evt, int x, int y);
}


/// Manages world-space objects rendering and IO event handling
/// (selection, picking).
final class WorldManager: IWindowDrawer, IWindowEventSubrouter
{
	// Let's say we always have one camera spanning whole window.
	CameraContext camCtx;

	/// everything that will be rendered in draw call
	WorldRenderable[] components;

	void clear()
	{
		components.length = 0;
		foreach (ref arr; m_mouseReceivers)
			arr.length = 0;
		timeAccelerationFactor = 10;
	}

	this(Window wnd)
	{
		camCtx = new CameraContext(wnd);
		components.reserve(512);
	}

	// needed to handle server-side time acceleration
	short timeAccelerationFactor = 10;

	void draw(Window wnd, long usecsDelta)
	{
		// TODO: maybe spread load on a thread pool
		long worldTimePassed = usecsDelta * timeAccelerationFactor / 10;
		foreach (comp; components)
			comp.update(camCtx, worldTimePassed);
		// and sort them in Z-order, deepest components first
		// sort!((a, b) => a.depth < b.depth)(components[]);
		// apply camera transformation
		sfRenderWindow_setView(wnd.wnd, camCtx.camera.view);
		// render components on the window
		foreach (comp; components)
			comp.render(wnd);
	}

	unittest
	{
		int[5] arr = [3, 2, 1, 2, 2];
		sort(arr[0 .. 3]);
		assert(arr == [1, 2, 3, 2, 2]);
		assert(arr != [1, 2, 2, 3, 2]);
		assert(arr != [1, 2, 2, 2, 3]);
	}

	// Input event handling

	private IWorldMouseReceiver[][3] m_mouseReceivers;

	/// first layer of mouse receivers for overlay interface components
	@property ref IWorldMouseReceiver[] overlayMouseReceivers() { return m_mouseReceivers[0]; }
	/// second layer of mouse receivers for other world-space objects
	@property ref IWorldMouseReceiver[] worldMouseReceivers() { return m_mouseReceivers[1]; }
	/// third layer of mouse receivers for background mouse handling
	@property ref IWorldMouseReceiver[] backgroundMouseReceivers() { return m_mouseReceivers[2]; }

	RouteResult routeMousePos(Window wnd, const sfEvent* evt, int x, int y)
	{
		foreach (arr; m_mouseReceivers)
		{
			foreach (mr; arr)
			{
				if (mr.isMouseEventInteresting(wnd, evt, x, y))
					return RouteResult(mr);
			}
		}
		return RouteResult(null);
	}

	RouteResult routeKeyboard(Window wnd, const sfEvent* evt)
	{
		return RouteResult(null);
	}

	void handleWindowResize(Window wnd, const sfSizeEvent* evt)
	{
		camCtx.camera.screenSize = vec2ui(evt.width, evt.height);
	}
}
