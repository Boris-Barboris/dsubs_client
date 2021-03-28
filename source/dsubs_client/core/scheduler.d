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
module dsubs_client.core.scheduler;

import std.container.rbtree;
import std.experimental.logger;

public import core.time: Duration;
import core.time;
import core.stdc.stdlib;
import core.atomic;
import core.thread;
import core.sync.condition;
import core.sync.mutex;


/// Background thread that dispatches delayed delegates
final class Scheduler
{
	private struct DelayRecord
	{
		MonoTime when;
		void delegate() what;
		Object.Monitor lockToHold;
	}

	private
	{
		Thread m_thread;
		Condition m_cond;

		alias RecordCollection = RedBlackTree!(DelayRecord, "a.when < b.when", true);
		RecordCollection m_records;
		DelayRecord[] m_addQueue;
		Mutex m_recordsLock;
		shared bool m_stop = false;
	}

	this()
	{
		m_cond = new Condition(new Mutex());
		m_records = new RecordCollection();
		m_recordsLock = new Mutex();
		m_thread = new Thread(&proc);
	}

	void start()
	{
		m_thread.start();
	}

	void stop()
	{
		if (!cas(&m_stop, false, true))
			return;
		trace("stopping Scheduler...");
		synchronized(m_cond.mutex)
			m_cond.notify();
		m_thread.join(false);
		trace("OK");
	}

	/// execute delegate 'what' after 'after' time interval, while holding
	/// 'mutToHold' lock.
	void delay(void delegate() what, Duration after, Object.Monitor mutToHold = null)
	{
		assert(what !is null);
		assert(after > Duration.zero);
		MonoTime now = MonoTime.currTime;
		synchronized (m_recordsLock)
		{
			m_addQueue ~= DelayRecord(now + after, what, mutToHold);
		}
		synchronized(m_cond.mutex)
			m_cond.notify();
	}

	private void proc()
	{
		Duration tillWakeup;
		while (true)
		{
			bool frontReached = false;
			if (tillWakeup == Duration.zero)
			{
				synchronized(m_cond.mutex)
					m_cond.wait();
			}
			else
				if (tillWakeup > Duration.zero)
				{
					synchronized(m_cond.mutex)
						frontReached = !m_cond.wait(tillWakeup);
				}
				else
					frontReached = true;
			if (atomicLoad(m_stop))
				break;
			synchronized (m_recordsLock)
			{
				foreach (rec; m_addQueue)
					m_records.insert(rec);
				m_addQueue.length = 0;
			}
			if (m_records.empty)
			{
				tillWakeup = Duration.zero;
				continue;
			}
			if (frontReached)
			{
				DelayRecord firstRecord = m_records.front;
				// actually run the code
				{
					if (firstRecord.lockToHold)
						firstRecord.lockToHold.lock();
					scope(exit)
					{
						if (firstRecord.lockToHold)
							firstRecord.lockToHold.unlock();
					}
					try
					{
						firstRecord.what();
					}
					catch (Error e)
					{
						error(e);
						exit(1);
					}
				}
				m_records.removeFront();
			}
			// setup next wakeup
			if (m_records.empty)
				tillWakeup = Duration.zero;
			else
				tillWakeup = m_records.front.when - MonoTime.currTime;
		}
	}
}