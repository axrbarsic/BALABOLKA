import type { NextFunction, Request, Response } from "express";

export function isAuthorizedHeader(
  authorizationHeader: string | null | undefined,
  bearerToken: string,
): boolean {
  if (!bearerToken) {
    return true;
  }

  return authorizationHeader === `Bearer ${bearerToken}`;
}

export function unauthorizedBody() {
  return {
    error: "UNAUTHORIZED",
    message: "Missing or invalid bearer token.",
  };
}

export function createBearerAuthMiddleware(bearerToken: string) {
  return (request: Request, response: Response, next: NextFunction): void => {
    if (!isAuthorizedHeader(request.header("authorization"), bearerToken)) {
      response.status(401).json(unauthorizedBody());
      return;
    }

    next();
  };
}
