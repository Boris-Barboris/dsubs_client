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
module dsubs_client.game.wireui;

import std.algorithm: map, canFind;
import std.algorithm.comparison: min, max;

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


private
{
	enum int FONT = 14;
	enum int LABEL_WIDTH = 100;
}


final class WireUi
{
	private
	{
		Slider m_slider;
		Label m_label;
		Div m_div;
		int m_wireId;
		float m_maxLength;
	}

	this(int wireId, string wireName, float maxLength)
	{
		m_wireId = wireId;
		m_maxLength = maxLength;
		m_label = builder(new Label()).content(wireName).
			fontSize(FONT).fixedSize(vec2i(LABEL_WIDTH, 1)).build;
		m_slider = new Slider();
		m_slider.value = 0.0f;
		m_slider.onDragEnd += (float newValue) {
			Game.ciccon.sendMessage(cast(immutable) CICWireDesiredLengthReq(
				m_wireId, newValue * m_maxLength));
		};
		m_div = hDiv([m_label, m_slider]);
		m_div.fixedSize = vec2i(1, FONT + 8);
	}

	void updateDesiredLength(float desired)
	{
		m_slider.value = desired / m_maxLength;
	}

	@property Div rootDiv() { return m_div; }
}