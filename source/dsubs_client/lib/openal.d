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
module dsubs_client.lib.openal;

import core.sync.mutex;
import core.sync.condition;
import core.time;
import core.thread;

import std.algorithm;
import std.range;
import std.stdio;
import std.process;

import derelict.openal.al;

import dsubs_client.common;


private enum ALenum AL_GAIN_LIMIT_SOFT = 0x200E;


void loadAudioLib()
{
	if (!("ALSOFT_CONF" in environment))
		environment["ALSOFT_CONF"] = "alsoft.ini";
	DerelictAL.load();
	s_device = alcOpenDevice(null);
	if (s_device is null)
	{
		error("OpenAL unable to open audio device");
		s_noAudio = true;
		return;
	}
	s_context = alcCreateContext(s_device, null);
	openalcCheckErr("Unable to create audio context: ");
	alcMakeContextCurrent(s_context);
	openalcCheckErr("Unable to activate audio context: ");
	alDistanceModel(AL_NONE);
	openalcCheckErr("Unable to set distance model: ");

	float maxSoftGain;
	alGetFloatv(AL_GAIN_LIMIT_SOFT, &maxSoftGain);
	openalcCheckErr("Unable to query AL_GAIN_LIMIT_SOFT: ");
	trace("OpenAL AL_GAIN_LIMIT_SOFT = ", maxSoftGain);
}

void unloadAudioLib()
{
	if (s_noAudio)
		return;
	info("unloadAudioLib called");
	cleanupSoundResources();
	alcMakeContextCurrent(null);
	alcDestroyContext(s_context);
	alcCloseDevice(s_device);
	info("unloadAudioLib returning");
}

private __gshared
{
	ALCdevice* s_device;
	ALCcontext* s_context;
	bool s_noAudio;
	StreamingSoundSource[] s_sources;
}

pragma(inline)
private void openalcCheckErr(string msgStart)
{
	ALenum err = alcGetError(s_device);
	enforce(err == AL_NO_ERROR, msgStart ~ err.to!string);
}

pragma(inline)
private void openalCheckErr(string msgStart)
{
	ALenum err = alGetError();
	enforce(err == AL_NO_ERROR, msgStart ~ err.to!string);
}

/// Dispose of all sound sources
void cleanupSoundResources()
{
	if (s_noAudio)
		return;
	foreach (s; s_sources)
	{
		s.stop();
		s.dispose();
	}
	s_sources.length = 0;
}

/// Sound source that can be appended to. At most one buffer is enqueued, new
/// buffers will cause rewind. Works with 1-second samples.
final class StreamingSoundSource
{
	this()
	{
		if (s_noAudio)
			return;
		alGenSources(1, &source);
		openalCheckErr("Unable to create audio source: ");
		alSourcef(source, AL_MAX_GAIN, MAX_GAIN);
		openalCheckErr("Cannot set max gain: ");
		gain = 0.0f;
		s_sources ~= this;
		m_cond = new Condition(new Mutex());
		m_appenderThread = new Thread(&appenderThreadProc);
		m_appenderThread.start();
	}

	private
	{
		ALuint source;

		// enum float TARGET_MAX = short.max * 0.8f;
		enum float MAX_GAIN = float.max;	// +30 dB

		bool m_stopFlag;
		Condition m_cond;
		// Head of queue
		ALuint m_curBuf = ALuint.max;
		// Tail of queue
		ALuint m_nextBuf = ALuint.max;
		// thread that wakes up right before the current playing sample end and
		// appends the next sample.
		Thread m_appenderThread;
		Duration m_endMargin = msecs(50);
		MonoTime m_wakeupDeadline;
	}

	~this()
	{
		dispose();
	}

	@property bool isPlaying() const
	{
		if (s_noAudio)
			return true;
		ALint propVal;
		alGetSourcei(source, AL_SOURCE_STATE, &propVal);
		openalCheckErr("Cannot get source state: ");
		return propVal == AL_PLAYING;
	}

	private bool m_disposed;

	void dispose() @nogc
	{
		if (s_noAudio || m_disposed)
			return;
		alSourceStop(source);
		alDeleteSources(1, &source);
		if (m_curBuf != ALuint.max)
			alDeleteBuffers(1, &m_curBuf);
		if (m_nextBuf != ALuint.max)
			alDeleteBuffers(1, &m_nextBuf);
		m_disposed = true;
	}

	/// Asynchronously stops the internal thread.
	void stop()
	{
		if (!m_stopFlag)
		{
			m_stopFlag = true;
			m_cond.notifyAll();
		}
	}

	private void appenderThreadProc()
	{
		while (!m_stopFlag)
		{
			synchronized(m_cond.mutex)
			{
				swap(m_curBuf, m_nextBuf);
				if (m_curBuf is ALuint.max)
				{
					m_cond.wait();	// wait for sample
					continue;
				}
			}
			pullFinishedBuffers();
			alSourceQueueBuffers(source, 1, &m_curBuf);
			openalCheckErr("Cannot enqueue buffer: ");
			m_curBuf = ALuint.max;
			if (ensurePlaying())
			{
				m_wakeupDeadline = m_wakeupDeadline + seconds(1);
			}
			else
			{
				m_wakeupDeadline = MonoTime.currTime + seconds(1) - m_endMargin;
			}
			Thread.sleep(m_wakeupDeadline - MonoTime.currTime);
		}
	}

	/// The next sample to append to stream will be this one.
	void setNextSample(short[] samples, int srate)
	{
		if (s_noAudio)
			return;
		// trace("appending sound, ", samples.length, " samples, ", srate, " srate");
		ALuint newBuf;
		alGenBuffers(1, &newBuf);
		openalCheckErr("Cannot create new buffer: ");
		// short smax = samples.map!(s => abs(s).to!short).maxElement();
		// float mgain = 1.0f;
		// if (gain != 0.0f)
		// 	mgain = min(MAX_GAIN, TARGET_MAX / smax);
		// foreach (ref s; samples)
		// 	s = lrint(float(s) * mgain).to!short;
		alBufferData(newBuf, AL_FORMAT_MONO16, samples.ptr,
			(samples.length * short.sizeof).to!int, srate);
		openalCheckErr("Unable to fill audio buffer with data: ");
		// atomic buffer handle swap between m_nextBuf and newBuf
		synchronized(m_cond.mutex)
		{
			swap(newBuf, m_nextBuf);
			if (newBuf is ALuint.max)
				m_cond.notify();
		}
		// release old m_nextBuf
		if (newBuf !is ALuint.max)
		{
			alDeleteBuffers(1, &newBuf);
			openalCheckErr("Unable to delete m_nextBuf buffer: ");
		}
	}

	void appendWav(string path)
	{
		if (s_noAudio)
			return;
		short[] samples;
		int srate, byteCount;
		loadWavFile(path, samples, byteCount, srate);
		setNextSample(samples, srate);
	}

	@property void gain(float rhs)
	{
		if (s_noAudio)
			return;
		enforce(rhs <= MAX_GAIN && rhs >= 0.0f);
		alSourcef(source, AL_GAIN, rhs);
		openalCheckErr("Cannot set gain: ");
	}

	@property float gain()
	{
		if (s_noAudio)
			return 1.0f;
		float res;
		alGetSourcef(source, AL_GAIN, &res);
		openalCheckErr("Cannot get gain: ");
		return res;
	}

	/// returns true if was playing before, false if not
	private bool ensurePlaying()
	{
		bool res = isPlaying;
		if (!res)
		{
			alSourcePlay(source);
			openalCheckErr("Cannot play an audio source: ");
		}
		return res;
	}

	private void pullFinishedBuffers()
	{
		if (s_noAudio)
			return;
		ALuint oldBuf;
		ALint processed;
		alGetSourcei(source, AL_BUFFERS_PROCESSED, &processed);
		while(processed > 0)
		{
			alSourceUnqueueBuffers(source, 1, &oldBuf);
			openalCheckErr("Unable to unqueue buffer: ");
			alDeleteBuffers(1, &oldBuf);
			openalCheckErr("Unable to delete unqueued buffer: ");
			processed--;
		}
	}
}


/// load mono
void loadWavFile(string filename, out short[] samples, out int byteCount, out int srate)
{
	File f = File(filename, "rb");
	f.seek(4 + 4 + 4 + 4 + 4 + 2 + 2);
	int[] srateArr = f.rawRead(new int[1]);
	enforce(srateArr.length == 1, "unexpected eof in wav file");
	srate = srateArr[0];
	f.seek(40);
	int[] byteLen = f.rawRead(new int[1]);
	enforce(byteLen.length == 1, "unexpected eof in wav file");
	byteCount = byteLen[0];
	enforce(byteCount % 2 == 0, "not 16-bit PCM?");
	int sampleCount = (byteCount / short.sizeof).to!int;
	f.seek(44);
	samples = f.rawRead(new short[sampleCount]);
}