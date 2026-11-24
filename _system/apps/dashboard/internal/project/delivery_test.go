package project

import (
	"reflect"
	"testing"

	"github.com/systems42-org/systems42-dashboard/_system/apps/dashboard/internal/wiki"
)

func frPage(meta map[string]any) *wiki.Page {
	return &wiki.Page{Stem: "FR-001-x", Meta: meta}
}

// A metamodel that declares no delivery states gets the shipped ones.
func TestDeliveryVocabDefaults(t *testing.T) {
	vocab := BuildDeliveryVocab(nil, []map[string]any{{"name": "agile"}, {"name": "Own"}})
	if !reflect.DeepEqual(vocab.States, []string{"partial", "implemented", "outdated", "removed"}) {
		t.Errorf("states = %v", vocab.States)
	}
	story := map[string]any{"notation": "agile", "level": "story", "delivery": "implemented"}
	if d := FRDelivery(frPage(story), vocab); d["known"] != true || d["value"] != "implemented" {
		t.Errorf("story: %v", d)
	}
	for name, meta := range map[string]map[string]any{
		"epic":          {"notation": "agile", "level": "epic", "delivery": "implemented"},
		"partial story": {"notation": "agile", "level": "story", "delivery": "partial"},
		"kite use case": {"notation": "use-case", "level": "kite", "delivery": "implemented"},
		"unknown state": {"notation": "agile", "level": "story", "delivery": "done"},
	} {
		if d := FRDelivery(frPage(meta), vocab); d["known"] != false {
			t.Errorf("%s: %v", name, d)
		}
	}
	// a project's own notation that declares neither key has no rule of its own
	own := map[string]any{"notation": "own", "level": "anything", "delivery": "partial"}
	if d := FRDelivery(frPage(own), vocab); d["known"] != true {
		t.Errorf("own notation: %v", d)
	}
}

// What the metamodel declares wins over the defaults.
func TestDeliveryVocabFromMetamodel(t *testing.T) {
	vocab := BuildDeliveryVocab([]string{"implemented", "verified"}, []map[string]any{{
		"name":                 "agile",
		"implementable_levels": []any{"story", "epic"},
		"delivery_states":      []any{"implemented", "verified", "done"},
	}})
	cases := []struct {
		level, value string
		known        bool
	}{
		{"story", "verified", true},
		{"epic", "implemented", true},
		{"story", "outdated", false}, // no state of the type any more
		{"story", "done", false},     // the notation alone does not make a state
		{"feature", "verified", false},
	}
	for _, c := range cases {
		d := FRDelivery(frPage(map[string]any{"notation": "agile", "level": c.level, "delivery": c.value}), vocab)
		if d["known"] != c.known {
			t.Errorf("%s %s: known = %v, want %v", c.level, c.value, d["known"], c.known)
		}
	}
}
