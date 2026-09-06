# Intentionally empty at this level: only environments/prod is ever
# actually `init`/`plan`/`apply`'d (it instantiates the modules and holds
# the real outputs). This file exists for structural symmetry with
# versions.tf/providers.tf/variables.tf/locals.tf, which environments/prod
# symlinks rather than duplicates.
