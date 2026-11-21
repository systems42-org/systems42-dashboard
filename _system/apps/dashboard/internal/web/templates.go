package web

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"path"
	"strings"
	"sync"

	"github.com/nikolalohinski/gonja/v2/builtins"
	controlStructures "github.com/nikolalohinski/gonja/v2/builtins/control_structures"
	"github.com/nikolalohinski/gonja/v2/config"
	"github.com/nikolalohinski/gonja/v2/exec"
	"github.com/nikolalohinski/gonja/v2/loaders"
	"github.com/nikolalohinski/gonja/v2/nodes"
	"github.com/nikolalohinski/gonja/v2/parser"
	"github.com/nikolalohinski/gonja/v2/tokens"
)

// Engine renders the shared Jinja2 templates in templates/ using gonja/v2
// with four targeted compatibility shims identified by the Phase 0 spike:
//
//  1. N-tuple unpacking in {% for a, b, c in ... %} (base.html, _list.html)
//  2. Running child top-level from/import/set/macro statements when extending
//  3. Module-scoped {% from ... import ... %} so macros see siblings & imports
//  4. Preserving Safe on {% set x %}...{% endset %} block captures (crumbs_html)
type Engine struct {
	fsys   fs.FS
	loader *fsLoader
	cfg    *config.Config
	env    *exec.Environment

	mu    sync.RWMutex
	cache map[string]*exec.Template
}

// EngineFuncs supplies the Flask-equivalent template globals.
type EngineFuncs struct {
	StaticURL func(filename string) string
	ListSpec  func(typeName string) map[string]any
}

// NewEngine creates a Jinja2 template engine over fsys (typically embedded templates/).
func NewEngine(fsys fs.FS, funcs EngineFuncs) *Engine {
	cfg := config.New()
	cfg.AutoEscape = true

	e := &Engine{
		fsys:  fsys,
		cfg:   cfg,
		cache: map[string]*exec.Template{},
	}
	e.loader = &fsLoader{fsys: fsys, root: "."}

	cs := exec.NewControlStructureSet(map[string]parser.ControlStructureParser{})
	cs.Update(builtins.ControlStructures)
	_ = cs.Replace("for", multiForParser)
	_ = cs.Replace("from", e.moduleFromParser)
	_ = cs.Replace("set", safeSetParser)

	filters := exec.NewFilterSet(map[string]exec.FilterFunction{})
	filters.Update(builtins.Filters)
	_ = filters.Replace("tojson", htmlSafeToJSON)

	globalCtx := builtins.GlobalFunctions.Inherit().Update(builtins.GlobalVariables)
	staticURL := funcs.StaticURL
	if staticURL == nil {
		staticURL = func(name string) string { return "/static/" + name }
	}
	listSpec := funcs.ListSpec
	if listSpec == nil {
		listSpec = func(typeName string) map[string]any {
			return map[string]any{"type": typeName, "orders": []any{}}
		}
	}
	globalCtx.Set("static_url", staticURL)
	globalCtx.Set("list_spec", listSpec)
	globalCtx.Set("csp_nonce", func() string { return "" })
	globalCtx.Set("url_for", func(params *exec.VarArgs) *exec.Value {
		if len(params.Args) > 0 && params.Args[0].String() == "static" {
			if fn, ok := params.KwArgs["filename"]; ok {
				return exec.AsValue("/static/" + fn.String())
			}
		}
		return exec.AsValue("/")
	})

	e.env = &exec.Environment{
		Context:           globalCtx,
		Filters:           filters,
		ControlStructures: cs,
		Tests:             builtins.Tests,
		Methods:           builtins.Methods,
	}
	return e
}

// Template returns a cached compiled template for name.
func (e *Engine) Template(name string) (*exec.Template, error) {
	resolved, err := e.loader.Resolve(name)
	if err != nil {
		return nil, err
	}
	e.mu.RLock()
	tpl, ok := e.cache[resolved]
	e.mu.RUnlock()
	if ok {
		return tpl, nil
	}
	tpl, err = exec.NewTemplate(resolved, e.cfg, e.loader, e.env)
	if err != nil {
		return nil, err
	}
	e.mu.Lock()
	e.cache[resolved] = tpl
	e.mu.Unlock()
	return tpl, nil
}

// Render compiles (if needed) and renders name with data into wr.
func (e *Engine) Render(wr io.Writer, name string, data map[string]any) error {
	tpl, err := e.Template(name)
	if err != nil {
		return err
	}
	return e.executeTemplate(tpl, wr, data)
}

// RenderSource parses and executes an inline template string with access to
// the engine's embedded templates (for {% from %}, {% extends %}, {% include %}).
func (e *Engine) RenderSource(wr io.Writer, source string, data map[string]any) error {
	shifted := loaders.MustNewShiftedLoader("__inline__", strings.NewReader(source), e.loader)
	tpl, err := exec.NewTemplate("__inline__", e.cfg, shifted, e.env)
	if err != nil {
		return err
	}
	return e.executeTemplate(tpl, wr, data)
}

func (e *Engine) executeTemplate(tpl *exec.Template, wr io.Writer, data map[string]any) error {
	ctx := e.env.Context.Inherit()
	if data != nil {
		ctx.Update(exec.NewContext(data))
	}
	r := exec.NewRenderer(&exec.Environment{
		Tests:             e.env.Tests,
		Filters:           e.env.Filters,
		ControlStructures: e.env.ControlStructures,
		Context:           ctx,
		Methods:           e.env.Methods,
	}, wr, e.cfg, e.loader, tpl)

	// Collect non-root templates in the inheritance chain (root is walked by
	// r.Execute; child templates' top-level from/import/set/macro statements
	// would otherwise be skipped by gonja).
	var chain []*nodes.Template
	for cur := tpl.Root(); cur != nil && cur.Parent != nil; cur = cur.Parent {
		chain = append(chain, cur)
	}
	for i := len(chain) - 1; i >= 0; i-- {
		if err := runTopLevelDefs(r, chain[i]); err != nil {
			return err
		}
	}
	return r.Execute()
}

func runTopLevelDefs(r *exec.Renderer, root *nodes.Template) error {
	for _, node := range root.Nodes {
		csb, ok := node.(*nodes.ControlStructureBlock)
		if !ok {
			continue
		}
		switch csb.Name {
		case "from", "import", "set", "macro":
			if cs, ok := csb.ControlStructure.(exec.ControlStructure); ok {
				if err := cs.Execute(r, csb); err != nil {
					return err
				}
			}
		}
	}
	return nil
}

// htmlSafeToJSON matches Flask/Jinja2's htmlsafe_dumps: Go's encoding/json
// already escapes <, >, & as \u003c, \u003e, \u0026; we also escape single
// quotes and mark the JSON safe so it can sit inside <script> or single-quoted
// HTML attributes without double-escaping.
func htmlSafeToJSON(_ *exec.Evaluator, in *exec.Value, _ *exec.VarArgs) *exec.Value {
	b, err := json.Marshal(in.Interface())
	if err != nil {
		return exec.ValueError(err)
	}
	s := strings.ReplaceAll(string(b), "'", `\u0027`)
	return exec.AsSafeValue(s)
}

// --- OS-independent fs.FS loader -------------------------------------------

type fsLoader struct {
	fsys fs.FS
	root string
}

func (l *fsLoader) Resolve(name string) (string, error) {
	cleaned := strings.TrimPrefix(path.Clean(path.Join(l.root, name)), "/")
	if cleaned == "" || cleaned == "." {
		return "", fmt.Errorf("invalid template path %q", name)
	}
	f, err := l.fsys.Open(cleaned)
	if err != nil {
		return "", fmt.Errorf("unknown template %q: %w", name, err)
	}
	_ = f.Close()
	return cleaned, nil
}

func (l *fsLoader) Read(name string) (io.Reader, error) {
	resolved, err := l.Resolve(name)
	if err != nil {
		return nil, err
	}
	data, err := fs.ReadFile(l.fsys, resolved)
	if err != nil {
		return nil, err
	}
	return bytes.NewReader(data), nil
}

func (l *fsLoader) Inherit(from string) (loaders.Loader, error) {
	if from == "" {
		return &fsLoader{fsys: l.fsys, root: l.root}, nil
	}
	resolved, err := l.Resolve(from)
	if err != nil {
		return nil, err
	}
	dir := path.Dir(resolved)
	return &fsLoader{fsys: l.fsys, root: dir}, nil
}

// --- Shim 1: N-tuple {% for a, b, c in ... %} ------------------------------

type multiForControlStructure struct {
	Vars            []string
	ObjectEvaluator nodes.Expression
	IfCondition     nodes.Expression
	BodyWrapper     *nodes.Wrapper
	EmptyWrapper    *nodes.Wrapper
}

func (f *multiForControlStructure) Position() *tokens.Token { return f.BodyWrapper.Position() }
func (f *multiForControlStructure) String() string {
	t := f.Position()
	return fmt.Sprintf("MultiFor(Line=%d Col=%d)", t.Line, t.Col)
}

type loopInfo struct {
	index     int
	index0    int
	length    int
	revindex  int
	revindex0 int
	first     bool
	last      bool
	depth     int
	depth0    int
	prevItem  *exec.Value
	nextItem  *exec.Value
	lastValue *exec.Value
}

func (li *loopInfo) GetAttribute(name string) (*exec.Value, bool) {
	switch name {
	case "index":
		return exec.AsValue(li.index), true
	case "index0":
		return exec.AsValue(li.index0), true
	case "revindex":
		return exec.AsValue(li.revindex), true
	case "revindex0":
		return exec.AsValue(li.revindex0), true
	case "first":
		return exec.AsValue(li.first), true
	case "last":
		return exec.AsValue(li.last), true
	case "length":
		return exec.AsValue(li.length), true
	case "depth":
		return exec.AsValue(li.depth), true
	case "depth0":
		return exec.AsValue(li.depth0), true
	case "previtem", "PrevItem":
		return li.prevItem, true
	case "nextitem", "NextItem":
		return li.nextItem, true
	case "cycle", "Cycle":
		return exec.AsValue(func(va *exec.VarArgs) *exec.Value {
			if len(va.Args) == 0 {
				return exec.AsValue("")
			}
			return va.Args[li.index0%len(va.Args)]
		}), true
	case "changed", "Changed":
		return exec.AsValue(func(va *exec.VarArgs) *exec.Value {
			var cur *exec.Value
			if len(va.Args) == 1 {
				cur = va.Args[0]
			} else {
				items := make([]any, 0, len(va.Args))
				for _, a := range va.Args {
					items = append(items, a.Interface())
				}
				cur = exec.AsValue(items)
			}
			same := li.lastValue != nil && cur.EqualValueTo(li.lastValue)
			li.lastValue = cur
			return exec.AsValue(!same)
		}), true
	}
	return exec.AsValue(nil), false
}

func (f *multiForControlStructure) Execute(r *exec.Renderer, _ *nodes.ControlStructureBlock) error {
	obj := r.Eval(f.ObjectEvaluator)
	if obj.IsError() {
		return obj
	}
	var rows [][]*exec.Value
	obj.Iterate(func(_, _ int, key, value *exec.Value) bool {
		sub := r.Inherit()
		ctx := sub.Environment.Context
		vals := make([]*exec.Value, len(f.Vars))
		if len(f.Vars) == 1 {
			vals[0] = key
		} else if value != nil && len(f.Vars) == 2 {
			vals[0] = key
			vals[1] = value
		} else if !key.IsString() && key.Len() == len(f.Vars) {
			key.Iterate(func(i, _ int, item, _ *exec.Value) bool {
				if i < len(vals) {
					vals[i] = item
				}
				return true
			}, func() {})
		} else {
			vals[0] = key
			if value != nil && len(vals) > 1 {
				vals[1] = value
			}
		}
		for i, name := range f.Vars {
			ctx.Set(name, vals[i])
		}
		if f.IfCondition != nil {
			if !sub.Eval(f.IfCondition).IsTrue() {
				return true
			}
		}
		rows = append(rows, vals)
		return true
	}, func() {})

	if len(rows) == 0 {
		if f.EmptyWrapper != nil {
			return r.Inherit().ExecuteWrapper(f.EmptyWrapper)
		}
		return nil
	}
	depth := 1
	if parentLoop, ok := r.Environment.Context.Get("loop"); ok {
		if p, ok := parentLoop.(*loopInfo); ok {
			depth = p.depth + 1
		}
	}
	li := &loopInfo{first: true, length: len(rows), depth: depth, depth0: depth - 1}
	for idx, vals := range rows {
		sub := r.Inherit()
		ctx := sub.Environment.Context
		for i, name := range f.Vars {
			ctx.Set(name, vals[i])
		}
		li.index0 = idx
		li.index = idx + 1
		li.first = idx == 0
		li.last = idx+1 == len(rows)
		li.revindex = len(rows) - idx
		li.revindex0 = len(rows) - idx - 1
		if idx == 0 {
			li.prevItem = exec.AsValue(nil)
		} else if len(vals) == 1 {
			li.prevItem = rows[idx-1][0]
		} else {
			li.prevItem = exec.AsValue(rows[idx-1])
		}
		if idx == len(rows)-1 {
			li.nextItem = exec.AsValue(nil)
		} else if len(vals) == 1 {
			li.nextItem = rows[idx+1][0]
		} else {
			li.nextItem = exec.AsValue(rows[idx+1])
		}
		ctx.Set("loop", li)

		if err := sub.ExecuteWrapper(f.BodyWrapper); err != nil {
			var brk *controlStructures.LoopBreakError
			if errors.As(err, &brk) {
				break
			}
			var cont *controlStructures.LoopContinueError
			if errors.As(err, &cont) {
				continue
			}
			return err
		}
	}
	return nil
}

func multiForParser(p *parser.Parser, args *parser.Parser) (nodes.ControlStructure, error) {
	first := args.Match(tokens.Name)
	if first == nil {
		return nil, args.Error("Expected an identifier as first argument for 'for'-tag", nil)
	}
	vars := []string{first.Val}
	for args.Match(tokens.Comma) != nil {
		next := args.Match(tokens.Name)
		if next == nil {
			return nil, args.Error("Loop variable must be an identifier", nil)
		}
		vars = append(vars, next.Val)
	}
	if args.Match(tokens.In) == nil {
		return nil, args.Error("Expected keyword 'in'.", nil)
	}
	objEval, err := args.ParseExpression()
	if err != nil {
		return nil, err
	}
	cs := &multiForControlStructure{Vars: vars, ObjectEvaluator: objEval}
	if args.MatchName("if") != nil {
		cond, err := args.ParseExpression()
		if err != nil {
			return nil, err
		}
		cs.IfCondition = cond
	}
	if !args.End() {
		return nil, args.Error("Malformed for-loop args.", nil)
	}
	wrapper, endargs, err := p.WrapUntil("else", "endfor")
	if err != nil {
		return nil, err
	}
	cs.BodyWrapper = wrapper
	if wrapper.EndTag == "else" {
		if !endargs.End() {
			return nil, endargs.Error("'else' tag does not accept arguments", nil)
		}
		emptyW, endargs2, err := p.WrapUntil("endfor")
		if err != nil {
			return nil, err
		}
		cs.EmptyWrapper = emptyW
		endargs = endargs2
	}
	if !endargs.End() {
		return nil, endargs.Error("'endfor' tag does not accept arguments", nil)
	}
	return cs, nil
}

// --- Shim 2: Module-scoped {% from ... import ... %} -----------------------

type moduleFromImport struct {
	engine             *Engine
	location           *tokens.Token
	filenameExpression nodes.Expression
	as                 map[string]string
}

func (f *moduleFromImport) Position() *tokens.Token { return f.location }
func (f *moduleFromImport) String() string {
	return fmt.Sprintf("ModuleFromImport(Line=%d Col=%d)", f.location.Line, f.location.Col)
}

func (f *moduleFromImport) Execute(r *exec.Renderer, _ *nodes.ControlStructureBlock) error {
	fv := r.Eval(f.filenameExpression)
	if fv.IsError() {
		return fv
	}
	filename := fv.String()
	tpl, err := f.engine.Template(filename)
	if err != nil {
		return fmt.Errorf("unable to load template %q: %w", filename, err)
	}
	modR := r.Inherit()
	modR.Template = tpl
	modR.RootNode = tpl.Root()
	if err := runTopLevelDefs(modR, tpl.Root()); err != nil {
		return err
	}
	for name, node := range tpl.Macros() {
		fn, err := exec.MacroNodeToFunc(node, modR)
		if err != nil {
			return fmt.Errorf("unable to import macro %q from %q: %w", name, filename, err)
		}
		modR.Environment.Context.Set(name, fn)
	}
	for alias, name := range f.as {
		val, ok := modR.Environment.Context.Get(name)
		if !ok {
			return fmt.Errorf("macro %q not found in %q", name, filename)
		}
		r.Environment.Context.Set(alias, val)
	}
	return nil
}

func (e *Engine) moduleFromParser(p *parser.Parser, args *parser.Parser) (nodes.ControlStructure, error) {
	cs := &moduleFromImport{
		engine:   e,
		location: p.Current(),
		as:       map[string]string{},
	}
	filename, err := args.ParseExpression()
	if err != nil {
		return nil, err
	}
	cs.filenameExpression = filename
	if args.MatchName("import") == nil {
		return nil, args.Error("Expected import keyword", args.Current())
	}
	for !args.End() {
		name := args.Match(tokens.Name)
		if name == nil {
			return nil, args.Error("Expected macro name (identifier)", args.Current())
		}
		if args.MatchName("as") != nil {
			alias := args.Match(tokens.Name)
			if alias == nil {
				return nil, args.Error("Expected macro alias name (identifier)", nil)
			}
			cs.as[alias.Val] = name.Val
		} else {
			cs.as[name.Val] = name.Val
		}
		if tok := args.MatchName("with", "without"); tok != nil {
			if args.MatchName("context") != nil {
				break
			}
			args.Stream().Backup()
		}
		if args.End() {
			break
		}
		if args.Match(tokens.Comma) == nil {
			return nil, args.Error("Expected ','", nil)
		}
	}
	return cs, nil
}

// --- Shim 3: Safe block-set ({% set x %}...{% endset %}) -------------------

type safeSetControlStructure struct {
	location    *tokens.Token
	target      nodes.Expression
	expression  nodes.Expression
	condition   nodes.Expression
	alternative nodes.Expression
	body        *nodes.Wrapper
}

func (s *safeSetControlStructure) Position() *tokens.Token { return s.location }
func (s *safeSetControlStructure) String() string {
	return fmt.Sprintf("SafeSet(Line=%d Col=%d)", s.location.Line, s.location.Col)
}

func (s *safeSetControlStructure) Execute(r *exec.Renderer, _ *nodes.ControlStructureBlock) error {
	var value *exec.Value
	if s.body != nil {
		var buf bytes.Buffer
		sub := r.Inherit()
		sub.Output = &buf
		if err := sub.ExecuteWrapper(s.body); err != nil {
			return err
		}
		value = exec.AsSafeValue(buf.String())
	} else if s.condition != nil && s.alternative != nil {
		cond := r.Eval(s.condition)
		if cond.IsError() {
			return cond
		}
		if !cond.IsNil() && cond.IsTrue() {
			value = r.Eval(s.expression)
		} else {
			value = r.Eval(s.alternative)
		}
	} else {
		value = r.Eval(s.expression)
	}
	if value == nil {
		return fmt.Errorf("invalid value in 'set' tag")
	}
	if value.IsError() {
		return value
	}
	switch n := s.target.(type) {
	case *nodes.Name:
		// Store *exec.Value directly so Safe=true on block-set survives lookup.
		r.Environment.Context.Set(n.Name.Val, value)
	case *nodes.GetAttribute:
		target := r.Eval(n.Node)
		if target.IsError() {
			return target
		}
		return target.Set(exec.AsValue(n.Attribute), value.Interface())
	case *nodes.GetItem:
		target := r.Eval(n.Node)
		if target.IsError() {
			return target
		}
		arg := r.Eval(n.Arg)
		if arg.IsError() {
			return arg
		}
		return target.Set(arg, value.Interface())
	default:
		return fmt.Errorf("illegal set target node %s", n)
	}
	return nil
}

func safeSetParser(p *parser.Parser, args *parser.Parser) (nodes.ControlStructure, error) {
	cs := &safeSetControlStructure{location: p.Current()}
	ident, err := args.ParseVariableOrLiteral()
	if err != nil {
		return nil, err
	}
	switch ident.(type) {
	case *nodes.Name, *nodes.Call, *nodes.GetItem, *nodes.GetAttribute:
		cs.target = ident
	default:
		return nil, fmt.Errorf("unexpected set target %s", ident)
	}
	if args.Match(tokens.Assign) == nil {
		if !args.End() {
			return nil, args.Error("Expected '=' or end of tag for block-set.", args.Current())
		}
		wrapper, endargs, err := p.WrapUntil("endset")
		if err != nil {
			return nil, err
		}
		if !endargs.End() {
			return nil, endargs.Error("endset takes no arguments", nil)
		}
		cs.body = wrapper
		return cs, nil
	}
	expr, err := args.ParseExpression()
	if err != nil {
		return nil, err
	}
	cs.expression = expr
	cond, alt, err := args.ParseCondition()
	if err != nil {
		return nil, err
	}
	if cond != nil {
		if alt == nil {
			return nil, args.Error("Malformed 'set' if else condition", args.Current())
		}
		cs.condition = cond
		cs.alternative = alt
	}
	if !args.End() {
		return nil, args.Error("Malformed 'set' tag args.", nil)
	}
	return cs, nil
}
