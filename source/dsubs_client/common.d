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

/// common imports for all client code
module dsubs_client.common;

public import std.exception: enforce;
public import std.experimental.logger: error, trace, info;
public import std.conv: to;
public import std.math;

public import gfm.math.vector;
public import gfm.math.matrix;

public import dsubs_common.api.constants: usecs_t;
public import dsubs_common.utils;

public import dsubs_client.core.utils;
public import dsubs_client.colorscheme;