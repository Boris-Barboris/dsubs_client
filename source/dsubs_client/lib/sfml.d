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
module dsubs_client.lib.sfml;

import std.meta: AliasSeq;

import derelict.sfml2.system;
import derelict.sfml2.window;
import derelict.sfml2.audio;
import derelict.sfml2.graphics;
import derelict.sfml2.network;

import dsubs_client.common;


version(linux)
{
	void initXLib()
	{
		import core.stdc.stdio;
		import core.stdc.stdlib;
		import core.sys.posix.dlfcn;

		info("Loading libX11 and requesting thread support");
		void *lh = dlopen("libX11.so", RTLD_NOW);
		if (lh == null)
			throw new Exception("failed to load libX11.so");
		extern(C) int function() fn = cast(int function()) dlsym(lh, "XInitThreads");
		fn();
	}
}


void loadSfmlLibraries()
{
	info("Loading CSFML shared libraries...");
	DerelictSFML2System.load();
	DerelictSFML2Window.load();
	// DerelictSFML2Audio.load();
	DerelictSFML2Graphics.load();
	// DerelictSFML2Network.load();
	info("OK!");
}

/// check if sfml event is mouse-related and has position
bool isMousePosEvent(in sfEvent* evt, out int x, out int y,
	out sfMouseButton mbutton, out float wheelDelta)
{
	if (evt.type == sfEvtMouseMoved)
	{
		x = evt.mouseMove.x;
		y = evt.mouseMove.y;
		mbutton = -1;
		wheelDelta = 0.0f;
		return true;
	}
	if (evt.type == sfEvtMouseButtonPressed)
	{
		x = evt.mouseButton.x;
		y = evt.mouseButton.y;
		mbutton = evt.mouseButton.button;
		wheelDelta = 0.0f;
		return true;
	}
	if (evt.type == sfEvtMouseButtonReleased)
	{
		x = evt.mouseButton.x;
		y = evt.mouseButton.y;
		mbutton = evt.mouseButton.button;
		wheelDelta = 0.0f;
		return true;
	}
	if (evt.type == sfEvtMouseWheelScrolled)
	{
		x = evt.mouseWheelScroll.x;
		y = evt.mouseWheelScroll.y;
		mbutton = -1;
		wheelDelta = evt.mouseWheelScroll.delta;
		return true;
	}
	return false;
}

bool isMousePosEvent(in sfEvent* evt)
{
	return (evt.type == sfEvtMouseMoved ||
			evt.type == sfEvtMouseButtonPressed ||
			evt.type == sfEvtMouseButtonReleased ||
			evt.type == sfEvtMouseWheelScrolled);
}

bool isMouseEvent(in sfEvent* evt)
{
	return (isMousePosEvent(evt) ||
			isMouseEnterLeave(evt));
}

bool isMouseEnterLeave(in sfEvent* evt)
{
	return (evt.type == sfEvtMouseEntered ||
			evt.type == sfEvtMouseLeft);
}

bool isKeyboardEvent(in sfEvent* evt)
{
	return (evt.type == sfEvtTextEntered ||
			evt.type == sfEvtKeyPressed ||
			evt.type == sfEvtKeyReleased);
}

// conversions
sfVector2f tosf(in vec2f v)
{
	return sfVector2f(v.x, v.y);
}

sfVector2f tosf(in vec2ui v)
{
	return sfVector2f(v.x, v.y);
}

sfVector2f tosf(in vec2i v)
{
	return sfVector2f(v.x, v.y);
}

sfIntRect tosf(in vec4i r)
{
	return sfIntRect(r[0], r[1], r[2], r[3]);
}

vec4i round(in sfFloatRect r)
{
	vec4i res;
	res[0] = lrint(r.left).to!int;
	res[1] = lrint(r.top).to!int;
	res[2] = lrint(r.width).to!int;
	res[3] = lrint(r.height).to!int;
	return res;
}

unittest
{
	vec4i v1 = vec4i(0, 1, 2, 3);
	sfIntRect v2 = tosf(v1);
	assert(v2.left == 0);
	assert(v2.top == 1);
	assert(v2.width == 2);
	assert(v2.height == 3);
}

sfVector2f tosf(in vec2d v)
{
	return sfVector2f(to!float(v.x), to!float(v.y));
}

// precision downscaling
sfTransform tosf(in mat3x3d m)
{
	sfTransform res;
	foreach (i; AliasSeq!(0, 1, 2, 6, 7, 8))
		res.matrix[i] = to!float(m.v[i]);
	// stupid screen-space sfml camera matrix with inverted Y
	foreach (j; AliasSeq!(3, 4, 5))
		res.matrix[j] = -to!float(m.v[j]);
	return res;
}

// precision upscaling
mat3x3d togfm(in sfTransform m)
{
	mat3x3d res;
	foreach (i; AliasSeq!(0, 1, 2, 6, 7, 8))
		res.v[i] = to!double(m.matrix[i]);
	// stupid screen-space sfml camera matrix with inverted Y
	foreach (j; AliasSeq!(3, 4, 5))
		res.v[j] = -to!double(m.matrix[j]);
	return res;
}
