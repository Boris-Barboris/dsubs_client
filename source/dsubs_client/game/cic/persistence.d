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
module dsubs_client.game.cic.persistence;

import std.stdio;
import std.file: rename;
import std.path;

import core.thread;
import core.time;

import standardpaths;

import dsubs_common.api.marshalling;
import dsubs_client.common;


class Persistable
{
	this(string name)
	{
		m_name = name;
	}

	protected
	{
		string m_name;

		/// Frequency of state save
		Duration m_saveInterval = seconds(20);
		MonoTime m_lastSave;
	}

	@property void saveInterval(Duration rhs) { m_saveInterval = rhs; }

	abstract immutable(ubyte)[] buildOnDiskMessage();

	protected abstract string getFileName();

	void saveToDiskIfPossible()
	{
		// disk overload protection
		if (MonoTime.currTime - m_lastSave <= m_saveInterval)
			return;
		immutable(ubyte)[] msgData = buildOnDiskMessage();
		auto saveFunc = {
			dumpToFile(msgData);
		};
		auto job = new Thread(saveFunc).start();
		m_lastSave = MonoTime.currTime;
	}

	private void dumpToFile(immutable(ubyte)[] stateToSave)
	{
		string fileNameStart = getFileName();
		string tempFileName = buildPath(
			writablePath(
				StandardPath.data, buildPath("dsubs", "cic"), FolderFlag.create),
			fileNameStart ~ ".data.part");
		string desiredFileName = buildPath(
			writablePath(
				StandardPath.data, buildPath("dsubs", "cic"), FolderFlag.create),
			fileNameStart ~ ".data");
		{
			auto f = File(tempFileName, "wb");
			f.rawWrite(stateToSave);
			f.sync();
		}
		// at least under posix this is atomic
		rename(tempFileName, desiredFileName);
	}

	protected MsgT* loadFromFile(MsgT)()
	{
		try
		{
			string fileNameStart = getFileName();
			string expectedFileName = buildPath(
				writablePath(
					StandardPath.data, buildPath("dsubs", "cic"), FolderFlag.create),
				fileNameStart ~ ".data");
			int[2] header;
			ubyte[] readBinData;
			{
				auto f = File(expectedFileName, "rb");
				ubyte[] hasRead = f.rawRead(cast(ubyte[]) header);
				assert(hasRead.length == 8);
				enforce(header[0] == MsgT.g_marshIdx, "incompatible verison");
				readBinData = new ubyte[header[1]];
				f.rawRead(readBinData);
			}
			MsgT* res = new MsgT();
			demarshalMessage(res, readBinData);
			return res;
		}
		catch (Exception ex)
		{
			error("Failure during ", m_name, " file load: ", ex.message);
			return null;
		}
	}
}