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
module dsubs_client.gui.scrollbar;

import std.algorithm.comparison: min, max;
import std.conv: to;
import std.experimental.logger;
import std.math;
import std.traits: isAssignable;

public import gfm.math.vector;

import derelict.sfml2.graphics;
import derelict.sfml2.system;
import derelict.sfml2.window;

import dsubs_client.core.window;
import dsubs_client.core.utils;
import dsubs_client.lib.sfml;
import dsubs_client.gui.element;


/// Container for a child GuiElement with vertical scrollbar
final class ScrollBar: GuiElement
{
	__gshared float g_scrollSpeed = 25.0f;

	private
	{
		float m_scrollPosition = 0.0f;
		GuiElement m_child;
	}

	invariant
	{
		assert(m_scrollPosition <= 0.0f);
	}

	@property GuiElement child() { return m_child; }

	this(GuiElement child)
	{
		assert(child !is null);
		super();
		m_sbBackgroundRect = sfRectangleShape_create();
		m_sbHandleRect = sfRectangleShape_create();
		sfRectangleShape_setOutlineThickness(m_sbHandleRect, 0);
		sfRectangleShape_setOutlineThickness(m_sbBackgroundRect, 0);
		sfRectangleShape_setFillColor(m_sbBackgroundRect, m_sbBackFillColor);
		sfRectangleShape_setFillColor(m_sbHandleRect, m_sbHandleColor);
		m_child = child;
		m_child.parent = this;
		m_child.parentViewport = &viewport();
		mouseTransparent = false;
		onMouseScroll += &handleMouseScroll;
		onMouseDown += &handleMouseDown;
		onMouseUp += &handleMouseUp;
		onMouseMove += &handleMouseMove;
	}

	private
	{
		sfRectangleShape* m_sbBackgroundRect;	/// scrollbar background rect
		sfRectangleShape* m_sbHandleRect;		/// scrollbar handle rect
		int m_scrollbarWidth = 10;
		int m_minSbHandleLength = 20;
		sfColor m_sbBackFillColor = sfColor(15, 15, 15, 50);
		sfColor m_sbHandleColor = sfWhite;
		bool m_sbVisible = true;
	}

	private
	{
		// y coordinate and size of the scrollbar handle
		float m_handleLength = 0.0f;
		float m_handleY = 0.0f;
	}

	mixin AppendSet!(vec2i, "position", "updateChildPosition();");

	mixin AppendSet!(vec2i, "size", "updateChild();");

	mixin GetSet!(sfColor, "sbBackFillColor",
		"sfRectangleShape_setFillColor(m_sbBackgroundRect, rhs);");

	mixin GetSet!(sfColor, "sbHandleColor",
		"sfRectangleShape_setFillColor(m_sbHandleRect, rhs);");

	mixin GetSet!(int, "scrollbarWidth", "updateChild();");

	mixin GetSet!(int, "minSbHandleLength", "updateSbVisual();");

	// sets up scrollbar visuals
	private void updateSbVisual()
	{
		if (m_child.size.y > 0.0f)
		{
			float frameRatio = size.y / m_child.size.y.to!float;
			if (frameRatio >= 1.0f)
			{
				// child can be fit inside container and we have no need in
				// the scrollbar, let's make it transparent
				m_sbVisible = false;
			}
			else
			{
				// let's calculate the handle position
				m_sbVisible = true;
				m_handleLength = max(m_minSbHandleLength, frameRatio * size.y);
				float x = -m_scrollPosition / m_maxScroll;
				m_handleY = x * (size.y - m_handleLength);
				int sbX = size.x - m_scrollbarWidth;
				sfRectangleShape_setPosition(m_sbBackgroundRect,
					sfVector2f(sbX, 0.0f));
				sfRectangleShape_setPosition(m_sbHandleRect,
					sfVector2f(sbX, m_handleY));
				sfRectangleShape_setSize(m_sbBackgroundRect,
					sfVector2f(m_scrollbarWidth, size.y));
				sfRectangleShape_setSize(m_sbHandleRect,
					sfVector2f(m_scrollbarWidth, m_handleLength));
			}
		}
		else
			m_sbVisible = false;
	}

	private void updateChild()
	{
		updateChildPosition();
		int newXSize = max(0, size.x - m_scrollbarWidth);
		final switch (m_child.layoutType)
		{
			case LayoutType.FIXED:
				m_child.size = vec2i(newXSize, m_child.size.y);
				break;
			case LayoutType.CONTENT:
				m_child.fitContent(Axis.X, newXSize);
				break;
			case LayoutType.GREEDY:
				m_child.size = vec2i(newXSize, size.y);
				break;
			case LayoutType.FRACT:
				assert(0, "FRACT layout unsupported by scrollbar");
		}
		updateMouseScroll(0);
		updateSbVisual();
	}

	private void updateChildPosition()
	{
		m_child.position = vec2i(position.x,
			lrint(position.y + m_scrollPosition).to!int);
		updateSbVisual();
	}

	override void childChanged(GuiElement child)
	{
		assert(child is m_child);
		// this ensures that m_scrollPosition is adequate and not out of bounds
		updateMouseScroll(0);
		updateChildPosition();
	}

	override void onHide()
	{
		m_child.onHide();
		super.onHide();
	}

	private void handleMouseScroll(int x, int y, float delta)
	{
		updateMouseScroll(delta);
		updateChildPosition();
	}

	private float m_maxScroll = 0.0f;

	private void updateMouseScroll(float delta, float speedGain = g_scrollSpeed)
	{
		m_maxScroll = m_child.size.y - size.y;
		if (m_maxScroll <= 0.0f)
			m_scrollPosition = 0.0f;
		else
		{
			m_scrollPosition += speedGain * delta;
			m_scrollPosition = fmin(0.0f, fmax(m_scrollPosition, -m_maxScroll));
		}
	}

	override void draw(Window wnd, long usecsDelta)
	{
		super.draw(wnd, usecsDelta);
		m_child.draw(wnd, usecsDelta);
		// child will set it's own scissors
		sfRenderWindow_setScissor(wnd.wnd, viewport.tosf);
		if (m_sbVisible)
		{
			sfRenderWindow_drawRectangleShape(wnd.wnd, m_sbBackgroundRect, &m_sfRst);
			sfRenderWindow_drawRectangleShape(wnd.wnd, m_sbHandleRect, &m_sfRst);
		}
	}

	override GuiElement getFromPoint(const sfEvent* evt, int x, int y)
	{
		if (super.getFromPoint(evt, x, y))
		{
			// first we check if we are pointing on the scrollbar
			if (m_sbVisible && x >= size.x - m_scrollbarWidth)
				return this;
			// we intercept all scrolling
			if (evt.type == sfEvtMouseWheelScrolled)
				return this;
			auto check = m_child.getFromPoint(evt, x, y);
			if (check)
				return check;
			return this;
		}
		return null;
	}

	private bool isOnScrollbarBody(int x, int y)
	{
		int lx = x - position.x;
		int ly = y - position.y;
		return (m_sbVisible && lx >= size.x - m_scrollbarWidth &&
			ly >= m_handleY && ly <= (m_handleY + m_handleLength));
	}

	private int m_prevY;

	private void handleMouseDown(int x, int y, sfMouseButton btn)
	{
		if (btn == sfMouseLeft && isOnScrollbarBody(x, y))
		{
			// user clicked on scrollbar, let's capture it
			requestMouseFocus();
			m_prevY = y;
		}
	}

	private void handleMouseUp(int x, int y, sfMouseButton btn)
	{
		if (btn == sfMouseLeft && mouseFocused)
			returnMouseFocus();
	}

	private void handleMouseMove(int x, int y)
	{
		if (mouseFocused && m_sbVisible)
		{
			int delta = y - m_prevY;
			float gain = size.y > 0 ? float(m_child.size.y) / size.y : 0.0f;
			updateMouseScroll(-delta, gain);
			updateChildPosition();
			m_prevY = y;
		}
	}
}
