package project

import (
	"regexp"
	"slices"
	"strings"
	"time"

	"github.com/systems42-org/systems42-dashboard/_system/apps/dashboard/internal/wiki"
)

// The delivery states and, per shipped notation, the levels that may carry
// one and the states it allows (meta FR-031). They apply where the
// repository's metamodel declares none, matching project/common.py.
var defaultDeliveryStates = []string{"partial", "implemented", "outdated", "removed"}

var defaultNotationDelivery = map[string]NotationDelivery{
	"agile":    {Levels: []string{"story"}, States: []string{"implemented", "outdated", "removed"}},
	"use-case": {Levels: []string{"sea", "fish"}, States: []string{"partial", "implemented", "outdated", "removed"}},
	"ears":     {Levels: []string{"requirement"}, States: []string{"implemented", "outdated", "removed"}},
	"prose":    {Levels: []string{"requirement"}, States: []string{"implemented", "outdated", "removed"}},
}

// NotationDelivery is what one notation rules about delivery: its
// implementable_levels and delivery_states. A nil list is no rule.
type NotationDelivery struct {
	Levels []string
	States []string
}

// DeliveryVocab is what the metamodel allows for a requirement's delivery
// (CON-006): the states of the type's field in declared order, and the rules
// per notation name in lower case.
type DeliveryVocab struct {
	States    []string
	Notations map[string]NotationDelivery
}

// BuildDeliveryVocab matches project/common.py's delivery_vocab(). states are
// the values of the type's delivery field, notations the metamodel's notation
// pages. Whatever they leave out comes from the shipped defaults.
func BuildDeliveryVocab(states []string, notations []map[string]any) DeliveryVocab {
	declared := func(n map[string]any, key string, fallback []string) []string {
		raw, ok := n[key].([]any)
		if !ok {
			return fallback
		}
		out := make([]string, 0, len(raw))
		for _, v := range raw {
			out = append(out, wiki.ScalarString(v))
		}
		return out
	}
	vocab := DeliveryVocab{States: states, Notations: map[string]NotationDelivery{}}
	if len(vocab.States) == 0 {
		vocab.States = append([]string{}, defaultDeliveryStates...)
	}
	for _, n := range notations {
		name := strings.ToLower(wiki.ScalarString(n["name"]))
		if _, seen := vocab.Notations[name]; seen {
			continue
		}
		def := defaultNotationDelivery[name]
		vocab.Notations[name] = NotationDelivery{
			Levels: declared(n, "implementable_levels", def.Levels),
			States: declared(n, "delivery_states", def.States),
		}
	}
	for name, def := range defaultNotationDelivery {
		if _, seen := vocab.Notations[name]; !seen {
			vocab.Notations[name] = def
		}
	}
	return vocab
}

var datePrefixRE = regexp.MustCompile(`^([0-9]{4}-[0-9]{2}-[0-9]{2})(?:[Tt ].*)?$`)

// deliveryChecked is the day of a delivery-checked timestamp, as written in
// its own time zone. Text that does not start with a date stays as written.
func deliveryChecked(v any) string {
	switch x := v.(type) {
	case nil, []any, map[string]any:
		return ""
	case time.Time:
		return x.Format("2006-01-02")
	}
	text := strings.TrimSpace(wiki.ScalarString(v))
	if m := datePrefixRE.FindStringSubmatch(text); m != nil {
		return m[1]
	}
	return text
}

// FRDelivery is a requirement's delivery status (meta FR-031, FR-048),
// matching project/requirements.py's fr_delivery(): value as written ("" for
// no delivery record), known when the metamodel allows the value on this
// page, and checked, the day of delivery-checked.
func FRDelivery(p *wiki.Page, vocab DeliveryVocab) map[string]any {
	value := ""
	switch raw := p.Meta["delivery"].(type) {
	case nil, []any, map[string]any:
	default:
		value = strings.TrimSpace(wiki.ScalarString(raw))
	}
	if value == "" {
		return map[string]any{"value": "", "known": false, "checked": ""}
	}
	rules := vocab.Notations[FRNotation(p)]
	known := slices.Contains(vocab.States, value) &&
		(rules.States == nil || slices.Contains(rules.States, value)) &&
		(rules.Levels == nil || slices.Contains(rules.Levels, FRLevel(p)))
	return map[string]any{"value": value, "known": known, "checked": deliveryChecked(p.Meta["delivery-checked"])}
}
