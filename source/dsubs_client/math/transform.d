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
module dsubs_client.math.transform;

import derelict.sfml2.graphics;
import derelict.sfml2.system;

import dsubs_client.lib.sfml: tosf;
public import dsubs_common.math;


/** Wrapper that converts double-precision dsubs transform to
single-precision sfml matrix. */
final class Transform: Transform2D
{
	private sfTransform m_sfmat;

	@property ref const(sfTransform) sfWorld()
	{
		if (m_dirty)
			rebuild();
		return m_sfmat;
	}

	protected override void rebuild()
	{
		super.rebuild();
		m_sfmat = world.tosf;
	}
}
