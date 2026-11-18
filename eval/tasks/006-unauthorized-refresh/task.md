# Refresh the token on 401

Route lookups carry an auth token from `ChorkiNetworkConfig.headersProvider`.
When the token expires, the API answers 401 and the viewer sees an error.

Add `ChorkiNetworkConfig.onUnauthorized` (`Future<bool> Function()?`). When
a route request gets a 401 and the callback is set, await it. If it returns
true, retry the request once (the headers provider supplies the new token).
If it returns false, or the retry is also 401, fail as `unauthorized`, as
today. The player itself must not depend on GetIt or on the app.

Follow CLAUDE.md's definition of done.
