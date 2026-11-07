from hypothesis import settings

# Tests run from a read-only checkout; keep the example database in memory.
settings.register_profile("default", database=None, max_examples=500)
settings.load_profile("default")
