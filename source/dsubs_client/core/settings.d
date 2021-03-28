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
module dsubs_client.core.settings;

import std.file;
import std.path;
import std.process: environment;

public import std.json;

import standardpaths;

import dsubs_client.common;


string configFileName()
{
	return buildPath(
		writablePath(
			StandardPath.config, buildPath("dsubs"), FolderFlag.create),
		"dsubs.json");
}


JSONValue readConfig()
{
	try
	{
		string contents = readText(configFileName());
		return parseJSON(contents);
	}
	catch (Exception ex)
	{
		JSONValue res = JSONValue();
		res.object = null;
		return res;
	}
}

void writeConfigField(T)(string key, T newVal)
{
	try
	{
		JSONValue oldConfig = readConfig();
		oldConfig.object[key] = JSONValue(newVal);
		write(configFileName(), toJSON(oldConfig, true));
	}
	catch (Exception ex)
	{
		error("Failed to write config: ", ex.msg);
	}
}