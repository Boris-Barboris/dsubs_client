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
module dsubs_client.gui.overlay;

import derelict.sfml2.graphics;

import dsubs_client.common;
import dsubs_client.math.transform;
import dsubs_client.render.camera;
import dsubs_client.core.utils;
import dsubs_client.gui.element;
import dsubs_client.input.router;
import dsubs_client.game.cameracontroller;


/// Overlay elements are usually tracking some point in world space while keeping
/// their screen-space size constant. All overlay elements by convention play friendly with camera
/// and therefore should pass or duplicate camera-related events to owner as well.
class OverlayElement: GuiElement
{
	mixin Readonly!(Overlay, "owner");

	/// Overlay elements may require hiding, or only small subset of them to be drawn
	private bool m_hidden;
	@property bool hidden() { return m_hidden; }
	@property void hidden(bool rhs)
	{
		if (rhs)
			onHide();
		m_hidden = rhs;
	}

	protected bool m_panning, m_dragging;

	this(Overlay owner)
	{
		m_owner = owner;
		// we clamp all overlay elements with overlay's viewport
		enableScissorTest = false;
		parentViewport = &owner.viewport();
		// overlays are mostly for clickable objects
		mouseTransparent = false;
		m_owner.add(this);
		// register handlers to proxy camera-related events to owner
		onMouseDown += &processMouseDown;
		onMouseUp += &processMouseUp;
		onMouseMove += &processMouseMove;
		onMouseScroll += &processMouseScroll;
		onMouseFocusLoss += { m_panning = m_dragging = false; };
	}

	private bool m_dropped;

	/// Remove overlay element from owner
	void drop()
	{
		if (!m_dropped)
		{
			onHide();
			m_owner.remove(this);
			m_dropped = true;
		}
	}

	private void processMouseDown(int x, int y, sfMouseButton btn)
	{
		if (btn == sfMouseRight)
		{
			m_owner.onPanStart(x, y);
			m_panning = true;
			requestMouseFocus();
		}
	}

	private void processMouseMove(int x, int y)
	{
		if (mouseFocused && m_panning)
			m_owner.onPan(x, y);
		else
			m_owner.onMouseMove(x, y);
	}

	private void processMouseUp(int x, int y, sfMouseButton btn)
	{
		if (btn == sfMouseRight)
		{
			m_panning = false;
			if (!m_dragging)
				returnMouseFocus();
		}
	}

	private void processMouseScroll(int x, int y, float delta)
	{
		m_owner.onMouseScroll(x, y, delta);
	}

	/// transforms center in screen-space to rounded left upper corner
	final vec2i center2lu(vec2d centerOnScreen)
	{
		return cast(vec2i) centerOnScreen - size / 2;
	}

	/// transforms left upper corner to center
	final vec2d lu2center(vec2i luOnScreen)
	{
		return cast(vec2d) luOnScreen + size / 2;
	}

	// We do not apply in-rect scissor test to overlay elements, we use overlay's viewport
	override void updateViewport()
	{
		m_viewport = *parentViewport;
	}

	/// Overlay elements must ignore mouse scroll in order to not block zooming
	override GuiElement getFromPoint(const sfEvent* evt, int x, int y)
	{
		if (evt.type == sfEvtMouseWheelScrolled)
			return null;
		return super.getFromPoint(evt, x, y);
	}

	/// Called by overlay when new coordinates of all tracked objects and camera
	/// state are ready to be applied to the element,
	/// right before actually drawing the element.
	abstract void onPreDraw();
}


/// Overlay container that indexes OverlayElements and dispatches
/// standard input events to them.
class Overlay: GuiElement
{
	protected bool[OverlayElement] m_elements;

	/// remove child overlay element
	void remove(OverlayElement el)
	{
		m_elements.remove(el);
		if (!el.hidden)
			el.onHide();
	}

	void clear()
	{
		foreach (el; m_elements.byKey)
		{
			if (!el.hidden)
				el.onHide();
			el.m_owner = null;
		}
		m_elements.clear();
	}

	void add(OverlayElement el)
	{
		m_elements[el] = true;
	}

	private bool m_hidden;
	mixin FinalGetSet!(bool, "hidden", "if (rhs) onHide();");

	override void onHide()
	{
		super.onHide();
		foreach (OverlayElement el; m_elements.byKey)
		{
			if (!el.hidden)
				el.onHide();
		}
	}

	abstract void onPanStart(int x, int y);
	abstract void onPan(int x, int y);

	/// must return coordinates, transformed from world space to window space.
	abstract vec2d world2screenPos(vec2d world);
	/// must return rotation, transformed from world space to window space.
	abstract double world2screenRot(double world);
	// ditto
	abstract vec2d screen2worldPos(vec2d screen);
	abstract double screen2worldRot(double screen);

	abstract double world2screenLength(double world);
	abstract double screen2worldLength(double screen);

	override void draw(Window wnd, long usecsDelta)
	{
		if (m_hidden)
			return;
		super.draw(wnd, usecsDelta);
		// fixme: render z-order is the same as mouse lookup z-order, must be inverse
		foreach (OverlayElement el; m_elements.byKey)
		{
			if (!el.hidden)
			{
				el.onPreDraw();
				el.draw(wnd, usecsDelta);
			}
		}
	}

	override GuiElement getFromPoint(const sfEvent* evt, int x, int y)
	{
		if (m_hidden)
			return null;
		if (rectContainsPoint(x, y))
		{
			// now let's find the element to route event to
			foreach (OverlayElement el; m_elements.byKey)
			{
				if (!el.hidden && !el.mouseTransparent)
				{
					GuiElement res = el.getFromPoint(evt, x, y);
					if (res)
						return res;
				}
			}
			return this;
		}
		return null;
	}
}


/// Overlay that spans 2D space and maintains the camera state and
/// common dragging-the-camera functionality.
class WorldSpaceOverlay: Overlay
{
	protected
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

	protected void processMouseDown(int x, int y, sfMouseButton btn)
	{
		if (btn == sfMouseRight)
		{
			onPanStart(x, y);
			requestMouseFocus();
		}
	}

	protected void processMouseUp(int x, int y, sfMouseButton btn)
	{
		if (btn == sfMouseRight)
			returnMouseFocus();
	}

	override void onPanStart(int x, int y)
	{
		m_mousePrevX = x;
		m_mousePrevY = y;
	}

	protected void processMouseMove(int x, int y)
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

	protected void processMouseScroll(int x, int y, float delta)
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