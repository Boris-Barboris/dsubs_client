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
module dsubs_client.render.render;

import core.time;
import core.thread;
import core.stdc.stdlib;
import core.sync.mutex;
import std.experimental.logger;

import derelict.sfml2.graphics;
import derelict.sfml2.window;

import dsubs_common.event;

import dsubs_client.common;
import dsubs_client.core.window;
import dsubs_client.input.router: InputRouter;


/// Anything that can draw on window
interface IWindowDrawer
{
	void draw(Window wnd, long usecsDelta);
}

/// Rendering thread wrapper, renders one window and dictates general form
/// of the rendering pipeline.
final class Render
{
	private Window m_window;
	private InputRouter m_router;

	IWindowDrawer guiRender;
	IWindowDrawer worldRender;

	@property Window window() { return m_window; }
	@property InputRouter router() { return m_router; }

	private Thread m_worker;	/// rendering thread
	private bool m_stopFlag;	/// true when rendering thread stop was requested

	this(Window wnd, InputRouter router)
	{
		assert(wnd);
		m_window = wnd;
		m_router = router;
	}

	/// start rendering thread
	void start(Object.Monitor mutex)
	{
		if (m_worker && m_worker.isRunning)
			throw new Exception("Render already started");
		m_stopFlag = false;
		trace("Deactivating window GL context in parent thread...");
		sfRenderWindow_setActive(m_window.wnd, false);
		trace("OK");
		info("Starting render thread...");
		m_worker = new Thread((){ render(mutex); }).start();
		info("OK");
	}

	/// non-blocking stop
	void stopAsync() { m_stopFlag = true; }

	/// blocking stop
	void stop()
	{
		m_stopFlag = true;
		if (m_worker && m_worker.isRunning)
		{
			trace("joining render thread...");
			m_worker.join(false);
			trace("OK");
		}
	}

	// these events are fired while holding render lock
	Event!(void delegate(long usecsDelta)) onPreRender;
	Event!(void delegate(long usecsDelta)) onPreGuiRender;
	Event!(void delegate(long usecsDelta)) onPostRender;

	/// clear handlers from on..Render events
	void clearHandlers()
	{
		onPreRender.clear();
		onPreGuiRender.clear();
		onPostRender.clear();
	}

	private float m_avgFps = 0.0f;
	@property float avgFps() const { return m_avgFps; }

	private enum int FPS_UPDATE_FREQ = 300;

	private MonoTime m_frameEndTime, m_frameStartTime;
	@property MonoTime frameEndTime() const { return m_frameEndTime; }
	@property MonoTime frameStartTime() const { return m_frameStartTime; }

	private uint m_frameCounter;
	/// wraps around
	@property uint frameCounter() const { return m_frameCounter; }

	/// Thread function
	private void render(scope Object.Monitor mutex)
	{
		try
		{
			MonoTime lastFpsMark = MonoTime.currTime;
			m_frameStartTime = m_frameEndTime = lastFpsMark;
			MonoTime prevTime = m_frameEndTime;
			long usecsDelta = 0;
			uint frameCounter = 0;
			while (!m_stopFlag)
			{
				m_window.resetView();
				sfRenderWindow_clear(m_window.wnd, COLORS.renderClear);
				if (m_stopFlag)
					break;
				synchronized(mutex)
				{
					m_frameStartTime = MonoTime.currTime;
					if (m_router)
						m_router.simulateMouseMove();
					onPreRender(usecsDelta);
					if (worldRender)
					{
						worldRender.draw(m_window, usecsDelta);
						m_window.resetView();
					}
					onPreGuiRender(usecsDelta);
					if (guiRender)
						guiRender.draw(m_window, usecsDelta);
					onPostRender(usecsDelta);
				}
				if (m_stopFlag)
					break;
				// present backbuffer, blocks until vsync
				sfRenderWindow_display(m_window.wnd);
				// update timings
				prevTime = m_frameEndTime;
				m_frameEndTime = MonoTime.currTime;
				usecsDelta = (m_frameEndTime - prevTime).total!"usecs";
				// update fps
				if (++m_frameCounter % FPS_UPDATE_FREQ == 0)
				{
					long totalMsecs = (m_frameEndTime - lastFpsMark).total!"msecs";
					m_avgFps = FPS_UPDATE_FREQ * 1000.0f / totalMsecs;
					// trace("FPS: ", m_avgFps);
					lastFpsMark = m_frameEndTime;
				}
			}
		}
		catch (Throwable err)
		{
			error("Render thread crashed: ", err.toString);
			exit(1);
		}
		trace("Exiting render loop, stop_flag is ", m_stopFlag);
	}
}
