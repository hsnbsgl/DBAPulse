using Microsoft.AspNetCore.Diagnostics;
using Microsoft.AspNetCore.Mvc;

namespace DBAPulse.Api;

/// <summary>Maps validation failures (ArgumentException and subclasses) to 400 ProblemDetails instead of 500.</summary>
public sealed class ArgumentExceptionHandler : IExceptionHandler
{
    private readonly IProblemDetailsService _problemDetails;
    public ArgumentExceptionHandler(IProblemDetailsService problemDetails) => _problemDetails = problemDetails;

    public async ValueTask<bool> TryHandleAsync(HttpContext httpContext, Exception exception, CancellationToken cancellationToken)
    {
        if (exception is not ArgumentException argumentException || httpContext.Response.HasStarted) return false;
        var detail = argumentException.ParamName is { Length: > 0 } parameterName
            ? argumentException.Message.Replace($" (Parameter '{parameterName}')", string.Empty, StringComparison.Ordinal)
            : argumentException.Message;
        httpContext.Response.StatusCode = StatusCodes.Status400BadRequest;
        return await _problemDetails.TryWriteAsync(new ProblemDetailsContext
        {
            HttpContext = httpContext,
            Exception = exception,
            ProblemDetails = new ProblemDetails { Status = StatusCodes.Status400BadRequest, Title = "Invalid request", Detail = detail }
        });
    }
}
