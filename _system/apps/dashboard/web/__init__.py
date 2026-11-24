"""The web layer: the routes, one module and one Flask blueprint per group.

The modules here may import Flask and every module below them, never `app`.
`app.py` registers their blueprints (tests/test_module_imports.py).
"""
