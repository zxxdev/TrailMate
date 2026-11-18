// Package link reads the frames TrailMate puts on key bindings and puts the
// messages back together. It mirrors TrailMate/core/Link.lua: both read
// and write the same frames, checked by testdata/vectors.txt.
package link

import (
	"encoding/base32"
	"fmt"
	"hash/crc32"
	"regexp"
	"strconv"
)

// Prefix starts the name of every frame. No frame with that name exists in
// the game, so pressing the key does nothing.
const Prefix = "TrailMateCarrier_"

// MaxPayload is the number of bytes one frame carries.
const MaxPayload = 32

// Frame is one part of a message, as the addon wrote it.
type Frame struct {
	Session string // the game session, 8 hex digits
	Seq     int    // frame number in the session, from 1
	Slot    int    // the inbox the addon loads next
	Msg     int    // message number in the session
	Part    int    // 1 to Count
	Count   int
	Payload []byte
}

var b32 = base32.StdEncoding.WithPadding(base32.NoPadding)

// CRC is the checksum of a frame's text (CRC-32, IEEE).
func CRC(s string) uint32 {
	return crc32.ChecksumIEEE([]byte(s))
}

func core(f Frame) string {
	return fmt.Sprintf("%s%s_%06X_%04X_%06X_%02X_%02X_%s", Prefix, f.Session, f.Seq, f.Slot, f.Msg, f.Part, f.Count,
		b32.EncodeToString(f.Payload))
}

// Action is the key binding action that carries a frame.
func Action(f Frame) string {
	c := core(f)
	return fmt.Sprintf("CLICK %s_%08X:LeftButton", c, CRC(c))
}

var actionRe = regexp.MustCompile(`^CLICK (` + Prefix +
	`([0-9A-F]{8})_([0-9A-F]+)_([0-9A-F]+)_([0-9A-F]+)_([0-9A-F]+)_([0-9A-F]+)_([A-Z2-7]+))_([0-9A-F]{8}):LeftButton$`)

// Parse reads a frame from an action. It accepts only exactly what Action
// writes, with a matching checksum.
func Parse(action string) (Frame, bool) {
	m := actionRe.FindStringSubmatch(action)
	if m == nil {
		return Frame{}, false
	}
	crc, err := strconv.ParseUint(m[9], 16, 32)
	if err != nil || uint32(crc) != CRC(m[1]) {
		return Frame{}, false
	}
	payload, err := b32.DecodeString(m[8])
	if err != nil || len(payload) > MaxPayload {
		return Frame{}, false
	}
	n := func(s string) int {
		v, _ := strconv.ParseInt(s, 16, 64)
		return int(v)
	}
	f := Frame{Session: m[2], Seq: n(m[3]), Slot: n(m[4]), Msg: n(m[5]), Part: n(m[6]), Count: n(m[7]),
		Payload: payload}
	if Action(f) != action || f.Part < 1 || f.Part > f.Count || f.Seq < 1 {
		return Frame{}, false
	}
	return f, true
}

// Message is a whole message: Kind 'M' a question, 'C' the character's
// context, 'N' a new conversation, 'P' only where to write.
type Message struct {
	Session string
	ID      int
	Kind    byte
	Text    string
}

type session struct {
	frames map[int]Frame
	ack    int
	slot   int
	parts  map[int][]byte
}

// Assembler collects frames in order and gives whole messages.
type Assembler struct {
	sessions map[string]*session
}

// NewAssembler starts with no sessions.
func NewAssembler() *Assembler {
	return &Assembler{sessions: map[string]*session{}}
}

// Add takes a frame (seen again or new) and returns the messages it
// completes. Frames are used in order: a message is whole when its last
// part arrives after all the frames before it.
func (a *Assembler) Add(f Frame) []Message {
	s := a.sessions[f.Session]
	if s == nil {
		s = &session{frames: map[int]Frame{}, parts: map[int][]byte{}}
		a.sessions[f.Session] = s
	}
	if f.Slot > s.slot {
		s.slot = f.Slot
	}
	if f.Seq <= s.ack {
		return nil
	}
	s.frames[f.Seq] = f
	var out []Message
	for {
		next, ok := s.frames[s.ack+1]
		if !ok {
			break
		}
		delete(s.frames, s.ack+1)
		s.ack++
		s.parts[next.Msg] = append(s.parts[next.Msg], next.Payload...)
		if next.Part == next.Count {
			body := s.parts[next.Msg]
			delete(s.parts, next.Msg)
			if len(body) > 0 {
				out = append(out, Message{Session: f.Session, ID: next.Msg, Kind: body[0], Text: string(body[1:])})
			}
		}
	}
	return out
}

// Ack is the last frame of a session received with all those before it.
func (a *Assembler) Ack(sessionID string) int {
	if s := a.sessions[sessionID]; s != nil {
		return s.ack
	}
	return 0
}

// Slot is the furthest inbox the addon of a session has announced.
func (a *Assembler) Slot(sessionID string) int {
	if s := a.sessions[sessionID]; s != nil {
		return s.slot
	}
	return 0
}
