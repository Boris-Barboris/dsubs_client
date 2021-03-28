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
module dsubs_client.gui.passwordfield;

import std.array: array;
import std.range: repeat, take;

import derelict.sfml2.graphics;

public import dsubs_common.mutstring;

import dsubs_client.gui.textfield;


final class PasswordField: TextField
{
	enum dchar PWDOT = '•';

	/// actual password will be here
	private dmutstring m_hiddenContent;

	this()
	{
		m_hiddenContent = _s(""d, 31);
	}

	alias content = typeof(super).content;

	@property override dmutstring content() { return m_hiddenContent; }

	@property override void content(dstring rhs)
	{
		str2mutCopy(rhs, m_hiddenContent);
		m_content.length = m_hiddenContent.length;
		m_content[0 .. $-1] = PWDOT;
		m_content[$-1] = 0;
		sfText_setUnicodeString(m_sfText, m_content.ptr);
		updateText();
	}

	override void insertAt(dchar c, size_t idx)
	out
	{
		assert(m_hiddenContent.length == m_content.length);
	}
	body
	{
		m_hiddenContent.insertAt(c, idx);
		m_content.insertAt(PWDOT, idx);
	}

	override void insertAt(dstring s, size_t idx)
	out
	{
		assert(m_hiddenContent.length == m_content.length);
	}
	body
	{
		m_hiddenContent.insertAt(s, idx);
		m_content.insertAt(repeat(PWDOT).take(s.length).array, idx);
	}

	override void removeAt(size_t idx)
	out
	{
		assert(m_hiddenContent.length == m_content.length);
	}
	body
	{
		m_hiddenContent.removeAt(idx);
		m_content.removeAt(idx);
	}

	override void removeInterval(size_t start, size_t end)
	out
	{
		assert(m_hiddenContent.length == m_content.length);
	}
	body
	{
		m_hiddenContent.removeInterval(start, end);
		m_content.removeInterval(start, end);
	}
}
