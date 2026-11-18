package link

import (
	"bufio"
	"encoding/hex"
	"os"
	"strconv"
	"strings"
	"testing"
)

// The frames in testdata/vectors.txt come from the addon's encoder
// (tools/link_vectors.lua): the bridge must read them back exactly.
func TestVectorsFromTheAddon(t *testing.T) {
	file, err := os.Open("testdata/vectors.txt")
	if err != nil {
		t.Fatal(err)
	}
	defer file.Close()
	frames, crcs := 0, 0
	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		fields := strings.Fields(scanner.Text())
		if len(fields) == 0 || strings.HasPrefix(fields[0], "#") {
			continue
		}
		switch fields[0] {
		case "crc":
			input := []byte{}
			if fields[1] != "-" {
				input, _ = hex.DecodeString(fields[1])
			}
			want, _ := strconv.ParseUint(fields[2], 10, 32)
			if got := CRC(string(input)); got != uint32(want) {
				t.Errorf("CRC(%q) = %d, the addon says %d", input, got, want)
			}
			crcs++
		case "frame":
			action := fields[1] + " " + fields[2]
			f, ok := Parse(action)
			if !ok {
				t.Fatalf("cannot read the addon's frame %s", action)
			}
			n := func(i int) int { v, _ := strconv.Atoi(fields[i]); return v }
			payload, _ := hex.DecodeString(fields[9])
			want := Frame{Session: fields[3], Seq: n(4), Slot: n(5), Msg: n(6), Part: n(7), Count: n(8), Payload: payload}
			if f.Session != want.Session || f.Seq != want.Seq || f.Slot != want.Slot || f.Msg != want.Msg ||
				f.Part != want.Part || f.Count != want.Count || string(f.Payload) != string(want.Payload) {
				t.Errorf("frame %s read as %+v, want %+v", action, f, want)
			}
			if Action(want) != action {
				t.Errorf("Action(%+v) = %s, the addon wrote %s", want, Action(want), action)
			}
			frames++
		}
	}
	if frames != 4 || crcs != 3 {
		t.Fatalf("read %d frames and %d checksums, want 4 and 3", frames, crcs)
	}
}

func TestParseRefusesWhatIsNotExactlyAFrame(t *testing.T) {
	good := Action(Frame{Session: "1A2B3C4D", Seq: 1, Slot: 1, Msg: 1, Part: 1, Count: 1, Payload: []byte("Mhola")})
	for _, bad := range []string{
		"ACTIONBUTTON1",
		"CLICK WitchcraftCarrier_V1_x:LeftButton",
		strings.Replace(good, "_01_01_", "_01_02_", 1), // checksum no longer matches
		strings.Replace(good, "1A2B3C4D", "1a2b3c4d", 1),
		good + " ",
	} {
		if _, ok := Parse(bad); ok {
			t.Errorf("Parse(%q) accepted it", bad)
		}
	}
	if _, ok := Parse(good); !ok {
		t.Fatal("Parse refused a good frame")
	}
}

func frames(session string, msg, firstSeq int, body string) []Frame {
	var out []Frame
	count := (len(body) + MaxPayload - 1) / MaxPayload
	for i := 0; i < count; i++ {
		end := (i + 1) * MaxPayload
		if end > len(body) {
			end = len(body)
		}
		out = append(out, Frame{Session: session, Seq: firstSeq + i, Slot: 5, Msg: msg, Part: i + 1, Count: count,
			Payload: []byte(body[i*MaxPayload : end])})
	}
	return out
}

func TestAssemblerWaitsForEveryFrameInOrder(t *testing.T) {
	a := NewAssembler()
	context := frames("1A2B3C4D", 1, 1, "CHunter level 34, Stranglethorn Vale, next step: Hunt for Yenniku")
	question := frames("1A2B3C4D", 2, 1+len(context), "M¿Qué hago ahora?")
	// The question's frame comes first, then the context's, out of order.
	if got := a.Add(question[0]); len(got) != 0 {
		t.Fatalf("a message before the frames ahead of it: %+v", got)
	}
	if a.Ack("1A2B3C4D") != 0 {
		t.Fatal("acknowledged a frame with a gap before it")
	}
	var got []Message
	for i := len(context) - 1; i >= 0; i-- {
		got = append(got, a.Add(context[i])...)
	}
	if len(got) != 2 || got[0].Kind != 'C' || got[1].Kind != 'M' || got[1].Text != "¿Qué hago ahora?" {
		t.Fatalf("messages = %+v", got)
	}
	if a.Ack("1A2B3C4D") != len(context)+1 || a.Slot("1A2B3C4D") != 5 {
		t.Fatalf("ack %d slot %d", a.Ack("1A2B3C4D"), a.Slot("1A2B3C4D"))
	}
	// A frame read again (the file is read many times) gives nothing new.
	if again := a.Add(question[0]); len(again) != 0 {
		t.Fatalf("a frame read twice gave %+v", again)
	}
}
