"""analysis_failure_test: passes when a target fails analysis with a message."""

def _impl(ctx):
    # An attribute with a transition is a list, even of one target.
    target = ctx.attr.target[0]
    if AnalysisFailureInfo not in target:
        return [AnalysisTestResultInfo(
            success = False,
            message = "expected %s to fail analysis with a message containing %r, but it analyzed fine" % (target.label, ctx.attr.message),
        )]
    messages = [c.message for c in target[AnalysisFailureInfo].causes.to_list()]
    ok = [m for m in messages if ctx.attr.message in m]
    return [AnalysisTestResultInfo(
        success = bool(ok),
        message = "expected a failure containing %r, got: %s" % (ctx.attr.message, messages),
    )]

analysis_failure_test = rule(
    implementation = _impl,
    attrs = {
        "message": attr.string(mandatory = True),
        "target": attr.label(
            mandatory = True,
            cfg = analysis_test_transition(settings = {
                "//command_line_option:allow_analysis_failures": True,
            }),
        ),
    },
    analysis_test = True,
    test = True,
)
