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
module dsubs_client.gui.dragdiv;

import std.algorithm;
import std.conv: to;
import std.experimental.logger;
import std.math;

import derelict.sfml2.graphics;
import derelict.sfml2.system;

import dsubs_client.lib.sfml;
import dsubs_client.core.window;
import dsubs_client.core.utils;
import dsubs_client.input.router;
import dsubs_client.gui.element;
import dsubs_client.gui.div;


/// Linear div, but internal borders can be dragged by mouse.
/// Behaves in proportional manner, maintaining relative fractions
/// of it's children.
class DragDiv: Div
{
	private
	{
		// Borders are draggable in edit mode only.
		// When it's false, it's just a standard div.
		bool m_editMode;
		sfColor m_hoverBorderColor = sfColor(255, 150, 150, 255);
		sfColor m_pressedBorderColor = sfColor(255, 25, 25, 255);

		// is some border being dragged?
		bool m_dragging;
		int m_prevMousePos;
		// if the border is being dragged, this is it's index
		int m_pressedBorderIdx = -1;
		// if the border is being hovered over, this is it's index
		int m_hoveredBorderIdx = -1;
	}

	this(DivType divType, GuiElement[] kids)
	{
		m_borderColor = sfColor(100, 100, 100, 255);
		foreach (kid; kids)
		{
			kid.layoutType = LayoutType.FRACT;
			if (kid.fraction == 0.0f)
				kid.fraction = 1.0f;
		}
		super(divType, kids);
		borderWidth = 5;
		onMouseDown += &handleMouseDown;
		onMouseUp += &handleMouseUp;
		onMouseMove += &handleMouseMove;
		onMouseLeave += &handleMouseLeave;
	}

	final @property bool editMode() const { return m_editMode; }

	final @property bool editMode(bool rhs)
	{
		m_editMode = rhs;
		if (!rhs)
		{
			m_dragging = false;
			returnMouseFocus();
			m_pressedBorderIdx = m_hoveredBorderIdx = -1;
			mouseTransparent = true;
		}
		else
			mouseTransparent = false;
		updateBorderColor();
		return m_editMode;
	}

	override void updateBorderColor()
	{
		super.updateBorderColor();
		if (!m_editMode)
			return;
		foreach (i, brd; m_cellBorders)
		{
			if (m_pressedBorderIdx == i)
				sfRectangleShape_setFillColor(brd, m_pressedBorderColor);
			else if (m_hoveredBorderIdx == i)
				sfRectangleShape_setFillColor(brd, m_hoverBorderColor);
		}
	}

	override GuiElement setChild(GuiElement newChild, size_t idx)
	{
		newChild.layoutType = LayoutType.FRACT;
		return super.setChild(newChild, idx);
	}

	private @property void dragging(bool rhs)
	{
		if (rhs != m_dragging)
		{
			if (rhs)
			{
				assert(m_pressedBorderIdx >= 0 &&
					m_pressedBorderIdx < m_cellBorders.length);
				sfRectangleShape_setFillColor(
					m_cellBorders[m_pressedBorderIdx],
					m_pressedBorderColor);
				requestMouseFocus();
			}
			else
			{
				assert(m_pressedBorderIdx >= 0 &&
					m_pressedBorderIdx < m_cellBorders.length);
				sfRectangleShape_setFillColor(
					m_cellBorders[m_pressedBorderIdx],
					m_borderColor);
				returnMouseFocus();
				onDragEnd(m_pressedBorderIdx);
				m_pressedBorderIdx = -1;	// not sure if here is the right place
			}
		}
		m_dragging = rhs;
	}

	private void moveBorderByDelta(int borderIdx, int delta)
	{
		m_updatingKids = true;
		float sumOfFractions = fold!((a, b) => a + b.fraction)(children, 0.0f);
		int pureBudget = pureChildrenBudget();
		if (pureBudget <= 0)
			return;
		float fractPerPixel = sumOfFractions / pureBudget;
		float fract1 = children[borderIdx].fraction;
		float fract2 = children[borderIdx + 1].fraction;
		// one child's fraction must be decreased by this, the other - increased
		float fractDelta = delta * fractPerPixel;
		// clamp to prevent negative fraction of childer after the drag
		if (fractDelta < 0.0f)
			fractDelta = fmax(-fract1, fractDelta);
		else
			fractDelta = fmin(fract2, fractDelta);
		children[borderIdx].fraction = fract1 + fractDelta;
		children[borderIdx + 1].fraction = fract2 - fractDelta;
		updateChildren();
	}

	private void handleMouseMove(int x, int y)
	{
		if (!m_editMode)
			return;
		x -= position.x;
		y -= position.y;
		int relVal = (fixedAxis == Axis.X ? y : x);
		int delta = relVal - m_prevMousePos;
		m_prevMousePos = relVal;
		if (m_dragging)
		{
			// border must be moved by delta
			assert(m_pressedBorderIdx >= 0 &&
				   m_pressedBorderIdx < m_cellBorders.length);
			moveBorderByDelta(m_pressedBorderIdx, delta);
		}
		else
		{
			// hover detection and m_hoveredBorderIdx calculation
			int oldHoverIdx = m_hoveredBorderIdx;
			m_hoveredBorderIdx = -1;
			foreach (i, sfBorderRect; m_cellBorders)
			{
				sfVector2f sfPos = sfRectangleShape_getPosition(sfBorderRect);
				sfVector2f sfSize = sfRectangleShape_getSize(sfBorderRect);
				if ((x >= sfPos.x && x < sfPos.x + sfSize.x) &&
					(y >= sfPos.y && y < sfPos.y + sfSize.y))
				{
					m_hoveredBorderIdx = i.to!int;
					break;
				}
			}
			if (oldHoverIdx != m_hoveredBorderIdx)
				updateBorderColor();
		}
	}

	private void handleMouseDown(int x, int y, sfMouseButton btn)
	{
		if (btn != sfMouseLeft)
			return;
		if (m_hoveredBorderIdx == -1)
			return;
		m_pressedBorderIdx = m_hoveredBorderIdx;
		dragging = true;
	}

	private void handleMouseUp(int x, int y, sfMouseButton btn)
	{
		if (btn != sfMouseLeft)
			return;
		dragging = false;
	}

	override void handleMouseFocusLoss()
	{
		super.handleMouseFocusLoss();
		dragging = false;
	}

	private void handleMouseLeave(IInputReceiver newOwner)
	{
		m_hoveredBorderIdx = -1;
		updateBorderColor();
	}

	Event!(void delegate(int borderIdx)) onDragEnd;
}


DragDiv hDragDiv(GuiElement[] children) { return new DragDiv(DivType.HORZ, children); }
DragDiv vDragDiv(GuiElement[] children) { return new DragDiv(DivType.VERT, children); }