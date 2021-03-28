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
module dsubs_client.core.utils;

import std.algorithm;
import std.container.array;
import std.range;


// Mixins to reduce boilerplate in object hierarchies

/** Generates final getter and virtual setter properties.
postupdateCode is injected right after field value update.
member field is expected to be named "m_" ~ fieldName, as in
hungarian scope notation. */
mixin template GetSet(T, string fieldName, string postupdateCode)
{
	mixin("final @property const(" ~ T.stringof ~ ") " ~ fieldName ~
		"() const { return m_" ~ fieldName ~ ";};");
	mixin("@property " ~ T.stringof ~ " " ~ fieldName ~ "(" ~ T.stringof ~ " rhs) " ~
		"{ m_" ~ fieldName ~ " = rhs;" ~ postupdateCode ~ "return m_" ~ fieldName  ~ ";}");
}

/// same as GetSet but with final setter
mixin template FinalGetSet(T, string fieldName, string postupdateCode)
{
	mixin("final @property const(" ~ T.stringof ~ ") " ~ fieldName ~
		"() const { return m_" ~ fieldName ~ ";};");
	mixin("final @property " ~ T.stringof ~ " " ~ fieldName ~ "(" ~ T.stringof ~ " rhs) " ~
		"{ m_" ~ fieldName ~ " = rhs;" ~ postupdateCode ~ "return m_" ~ fieldName  ~ ";}");
}

/// Append additional postupdateCode to setter of the base class
mixin template AppendSet(T, string fieldName, string postupdateCode)
{
	mixin("alias " ~ fieldName ~ " = typeof(super)." ~ fieldName ~ ";");
	mixin("override @property " ~ T.stringof ~ " " ~ fieldName ~ "(" ~ T.stringof ~ " rhs) " ~
		"{ super." ~ fieldName ~ " = rhs;" ~ postupdateCode ~ "return " ~ fieldName ~ ";}");
}

/// Replace postupdateCode in setter of the base class
mixin template RewriteSet(T, string fieldName, string postupdateCode)
{
	mixin("alias " ~ fieldName ~ " = typeof(super)." ~ fieldName ~ ";");
	mixin("override @property " ~ T.stringof ~ " " ~ fieldName ~ "(" ~ T.stringof ~ " rhs) " ~
		"{ m_" ~ fieldName ~ " = rhs;" ~ postupdateCode ~ "return m_" ~ fieldName ~ ";}");
}

/// mixes in private member named m_'fieldName' of type T, and
/// final getter for it.
mixin template Readonly(T, string fieldName)
{
	mixin("private " ~ T.stringof ~ " m_" ~ fieldName ~ ";");
	mixin("final @property inout(" ~ T.stringof ~ ") " ~ fieldName ~
		"() inout { return m_" ~ fieldName ~ ";};");
}


/// Returns builder wich is deduced from type of an argument, and allows to
/// chain property assignments in fluent form.
auto builder(T)(T base)
	if (is(T == class))
{
	static struct Builder(T)
	{
		private T m_data;

		@disable this();

		this(T data)
		{
			m_data = data;
		}

		T build()
		{
			return m_data;
		}

		Builder!T opDispatch(string name, ArgT)(ArgT rhs)
		{
			__traits(getMember, m_data, name) = rhs;
			return Builder!T(m_data);
		}
	}

	return Builder!T(base);
}