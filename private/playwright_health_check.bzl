"""playwright_health_check — one-shot readiness probe for a `playwright_server`.

Same shape as pg_health_check / temporal_health_check / kind_health_check:
exits 0 when the server's WS endpoint accepts a connection, non-0 otherwise.
itest's `service.health_check` retries until success or timeout.
"""

def _impl(ctx):
    out = ctx.actions.declare_file(ctx.label.name + ".sh")
    ctx.actions.expand_template(
        template = ctx.file._tmpl,
        output = out,
        substitutions = {
            "{ENDPOINT_VAR}": ctx.attr.endpoint_env,
        },
        is_executable = True,
    )
    return [DefaultInfo(executable = out)]

playwright_health_check = rule(
    implementation = _impl,
    attrs = {
        "endpoint_env": attr.string(
            default = "PLAYWRIGHT_SERVER_URL",
            doc = "Env var holding the ws://host:port URL to probe.",
        ),
        "_tmpl": attr.label(
            default = "//private:health_check.sh.tmpl",
            allow_single_file = True,
        ),
    },
    executable = True,
)
