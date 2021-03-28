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
module dsubs_client.gui.slider;

import std.algorithm: min, max;

import derelict.sfml2.graphics;
import derelict.sfml2.system;
import derelict.sfml2.window;

import dsubs_client.common;
import dsubs_client.lib.sfml;
import dsubs_client.core.window;
import dsubs_client.gui.element;
import dsubs_client.common;



final class Slider: GuiElement
{
	private
	{
		sfRectangleShape* m_rail;
		sfRectangleShape* m_handle;
		int m_railWidth = 4;
		int m_handleLength = 10;
		int m_handleWidth = 20;
		immutable Axis m_axis;

		// colors
		sfColor m_railColor = sfColor(100, 100, 100, 255);
		sfColor m_handleColor = sfColor(255, 255, 255, 255);
		sfColor m_handlePressedColor = sfColor(255, 150, 150, 255);

		float m_wheelGain = 0.05f;

		// dynamically calculated values
		float m_value = 0.0f;
		int m_railLen;
		int m_railMargin;	// distance between border and rail

		// mouse stuff
		bool m_dragging;
		int m_prevMousePos;
	}

	/// normalized handle position: [0, 1]
	@property float value() const { return m_value; }

	@property void value(float rhs)
	{
		bool changed = rhs != m_value;
		m_value = rhs;
		updateHandle();
		if (changed)
			onValueChanged(m_value);
	}

	invariant
	{
		assert(m_value >= 0.0f && m_value <= 1.0f);
	}

	this(Axis mainAxis = Axis.X)
	{
		super();
		mouseTransparent = false;
		m_axis = mainAxis;
		m_rail = sfRectangleShape_create();
		m_handle = sfRectangleShape_create();
		sfRectangleShape_setFillColor(m_rail, m_railColor);
		sfRectangleShape_setOutlineThickness(m_rail, 0.0f);
		sfRectangleShape_setFillColor(m_handle, m_handleColor);
		sfRectangleShape_setOutlineThickness(m_handle, 0.0f);
		onMouseScroll += &handleMouseScroll;
		onMouseDown += &handleMouseDown;
		onMouseUp += &handleMouseUp;
		onMouseMove += &handleMouseMove;
	}

	~this()
	{
		sfRectangleShape_destroy(m_rail);
		sfRectangleShape_destroy(m_handle);
	}

	mixin FinalGetSet!(sfColor, "railColor",
		"sfRectangleShape_setFillColor(m_rail, rhs);");

	mixin FinalGetSet!(int, "handleLength", "updateRail(); updateHandle();");
	mixin FinalGetSet!(int, "handleWidth", "updateRail(); updateHandle();");

	mixin FinalGetSet!(float, "wheelGain", "");

	override void updateSize()
	{
		super.updateSize();
		updateRail();
		updateHandle();
	}

	private void updateRail()
	{
		// let's calculate rectangle positions
		int oaxis = m_axis ^ 1;
		int totalLen = size[m_axis];
		int totalWidth = size[oaxis];

		m_railMargin = max(0, ceil(m_handleLength / 2.0f).to!int);
		// rail
		vec2i railPos, railSize;
		railPos[m_axis] = m_railMargin;
		railPos[oaxis] = (totalWidth - m_railWidth) / 2;
		railSize[m_axis] = max(1, totalLen - 2 * m_railMargin);
		railSize[oaxis] = m_railWidth;
		sfRectangleShape_setPosition(m_rail, railPos.tosf);
		sfRectangleShape_setSize(m_rail, railSize.tosf);
		m_railLen = railSize[m_axis];
	}

	private void updateHandle()
	{
		int oaxis = m_axis ^ 1;
		int totalWidth = size[oaxis];

		vec2i handlePos, handleSize;
		if (m_axis == Axis.X)
		{
			handlePos[m_axis] = lrint(m_railMargin + m_value * m_railLen -
				m_handleLength / 2.0f).to!int;
		}
		else
		{
			handlePos[m_axis] = lrint(size.y - m_railMargin - m_value * m_railLen -
				m_handleLength / 2.0f).to!int;
		}
		handlePos[oaxis] = (totalWidth - m_handleWidth) / 2;
		handleSize[m_axis] = m_handleLength;
		handleSize[oaxis] = m_handleWidth;
		sfRectangleShape_setPosition(m_handle, handlePos.tosf);
		sfRectangleShape_setSize(m_handle, handleSize.tosf);
	}

	override void draw(Window wnd, long usecsDelta)
	{
		super.draw(wnd, usecsDelta);
		sfRenderWindow_drawRectangleShape(wnd.wnd, m_rail, &m_sfRst);
		sfRenderWindow_drawRectangleShape(wnd.wnd, m_handle, &m_sfRst);
	}

	private @property void dragging(bool rhs)
	{
		if (rhs != m_dragging)
		{
			if (rhs)
			{
				sfRectangleShape_setFillColor(m_handle, m_handlePressedColor);
				requestMouseFocus();
			}
			else
			{
				sfRectangleShape_setFillColor(m_handle, m_handleColor);
				returnMouseFocus();
				onDragEnd(m_value);
			}
		}
		m_dragging = rhs;
	}

	private void handleMouseDown(int x, int y, sfMouseButton btn)
	{
		if (btn != sfMouseLeft)
			return;
		// transform x and y to local
		x -= position.x;
		y -= position.y;
		sfVector2f hpos = sfRectangleShape_getPosition(m_handle);
		sfVector2f hsize = sfRectangleShape_getSize(m_handle);
		if (x >= hpos.x && x < hpos.x + hsize.x &&
			y >= hpos.y && y < hpos.y + hsize.y)
		{
			m_prevMousePos = (m_axis == Axis.X ? x : y);
			dragging = true;
		}
		else
		{
			sfVector2f rpos = sfRectangleShape_getPosition(m_rail);
			sfVector2f rsize = sfRectangleShape_getSize(m_rail);
			// direct move to the position
			if (m_axis == Axis.X)
			{
				x = x - rpos.x.to!int;
				value = max(0.0f, min(1.0f, x / rsize.x));
			}
			else
			{
				y = y - rpos.y.to!int;
				value = max(0.0f, min(1.0f, y / rsize.y));
			}
			onDragEnd(m_value);
		}
	}

	private void handleMouseScroll(int x, int y, float delta)
	{
		value = max(0.0f, min(1.0f, m_value + m_wheelGain * delta));
		onDragEnd(m_value);
	}

	override void handleMouseFocusLoss()
	{
		super.handleMouseFocusLoss();
		dragging = false;
	}

	private void handleMouseUp(int x, int y, sfMouseButton btn)
	{
		if (btn != sfMouseLeft)
			return;
		dragging = false;
	}

	private void handleMouseMove(int x, int y)
	{
		if (!m_dragging)
			return;
		x -= position.x;
		y -= position.y;
		int relVal = (m_axis == Axis.X ? x : y);
		int delta = relVal - m_prevMousePos;
		if (m_axis == Axis.Y)
			delta = -delta;
		value = max(0.0f, min(1.0f, m_value + delta / float(m_railLen)));
		m_prevMousePos = relVal;
	}

	Event!(void delegate(float newVal)) onValueChanged;
	Event!(void delegate(float finalVal)) onDragEnd;
}