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
module dsubs_client.gui.collapsable;

import derelict.sfml2.graphics;

import dsubs_client.core.utils;
import dsubs_client.core.window;
import dsubs_client.gui.element;
import dsubs_client.gui.button;
import dsubs_client.gui.label;
import dsubs_client.gui.div;
import dsubs_client.render.shapes;


/// Collapsable vertical div container for another element
final class Collapsable: Div
{
	private
	{
		GuiElement m_child, m_childFiller;
		Div m_headerDiv;
		CircleShape m_titleTriangle;
		Button m_titleShapeButton;
		Button m_title;
		bool m_collapsed = true;
		int m_headerFontSize = 14;
	}

	@property bool collapsed() const { return m_collapsed; }

	mixin GetSet!(int, "headerFontSize",
		"m_title.fontSize = rhs; recalculate();");

	@property GuiElement child() { return m_child; }

	@property title(string newTitle)
	{
		m_title.content = newTitle;
	}

	this(GuiElement child, string title)
	{
		m_titleTriangle = new CircleShape(5.0f, 3);
		m_titleTriangle.fillColor = sfWhite;
		m_title = new Button();
		m_title.htextAlign = HTextAlign.LEFT;
		m_title.mouseTransparent = false;
		m_titleShapeButton = new Button();
		m_titleShapeButton.fixedSize(vec2i(16, 10));
		m_title.content = title;
		m_childFiller = filler(0);
		m_headerDiv = hDiv(cast(GuiElement[]) [m_titleShapeButton, m_title]);
		m_headerDiv.layoutType = layoutType.FIXED;
		super(DivType.VERT, [m_headerDiv, m_childFiller]);
		mouseTransparent = false;
		// layoutType = layoutType.FIXED;
		m_child = child;
		m_titleTriangle.rotation = 180.0f;
		m_titleShapeButton.onClick += &toggleCollapsed;
		m_title.onClick += &toggleCollapsed;
		headerFontSize = 14;
	}

	private void recalculate()
	{
		int divSize = m_headerFontSize + 4 + m_headerFontSize / 8;
		m_headerDiv.size = vec2i(divSize, divSize);
		if (!m_collapsed)
		{
			setChild(m_child, 1);
			size = vec2i(size.x, m_headerDiv.size.y + m_child.size.y);
			m_titleTriangle.rotation = 0.0f;
		}
		else
		{
			setChild(m_childFiller, 1);
			size = vec2i(size.x, m_headerDiv.size.y);
			m_titleTriangle.rotation = 180.0f;
		}
	}

	void toggleCollapsed()
	{
		m_collapsed = !m_collapsed;
		recalculate();
	}

	override void onBeforeChildrenDraw(Window wnd, long usecsDelta)
	{
		// draw shape on top of toggle button in a header
		m_titleTriangle.center = m_titleShapeButton.center;
		m_titleTriangle.render(wnd);
	}
}