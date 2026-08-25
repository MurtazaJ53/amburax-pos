"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";

import { apiMutation, getSession } from "@/lib/admin-api";
import { clearAdminWebMfaCookie, setAdminWebMfaCookie } from "@/lib/mfa";
import type { UserMfaStatusPayload, UserMfaVerifyPayload } from "@/lib/types";

function getOptionalField(formData: FormData, key: string) {
  return String(formData.get(key) || "").trim();
}

function getRequiredField(formData: FormData, key: string, label: string) {
  const value = getOptionalField(formData, key);
  if (!value) {
    throw new Error(`Missing ${label}.`);
  }
  return value;
}

/** A message a person can act on, rather than a wall of server text.
 *
 *  The raw error was being pasted onto the screen 220 characters at a time,
 *  which is how a stack trace ends up in front of a shopkeeper.
 */
function failureMessage(error: unknown, fallback: string): string {
  if (!(error instanceof Error) || !error.message) return fallback;
  const text = error.message.replace(/\s+/g, " ").trim();
  // Anything that looks like a payload or a trace is not for the reader.
  if (text.length > 140 || text.startsWith("{") || text.includes("Traceback")) {
    return fallback;
  }
  return text;
}

function buildRedirectUrl(params: Record<string, string>) {
  const searchParams = new URLSearchParams(params);
  return `/security?${searchParams.toString()}`;
}

export async function beginMfaEnrollmentAction(formData: FormData) {
  const returnTo = getOptionalField(formData, "returnTo");
  let target: string;

  try {
    await apiMutation<UserMfaStatusPayload>("/session/mfa/enroll/", {
      method: "POST",
      body: {},
    });
    target = buildRedirectUrl({ status: "pending", returnTo });
  } catch (error) {
    target = buildRedirectUrl({ status: "error", message: failureMessage(error, "Could not start setup."), returnTo });
  }

  revalidatePath("/security");
  // OUTSIDE the try. redirect() signals by throwing NEXT_REDIRECT, so calling
  // it inside one means the catch swallows its own success and reports the
  // redirect as a failure - every completed action said it had gone wrong.
  redirect(target);
}

export async function verifyMfaCodeAction(formData: FormData) {
  const purpose = getRequiredField(formData, "purpose", "purpose");
  const code = getRequiredField(formData, "code", "authentication code");
  const returnTo = getOptionalField(formData, "returnTo");

  let target: string;

  try {
    const result = await apiMutation<UserMfaVerifyPayload>("/session/mfa/verify/", {
      method: "POST",
      body: { purpose, code },
    });
    const session = await getSession();
    if (!result.status.security_stamp) {
      throw new Error("The server confirmed the code but sent no security stamp.");
    }
    await setAdminWebMfaCookie({
      userId: session.user.id,
      securityStamp: result.status.security_stamp,
      verifiedUntil: result.verified_until,
    });
    target =
      returnTo || buildRedirectUrl({ status: purpose === "enroll" ? "enabled" : "verified" });
  } catch (error) {
    target = buildRedirectUrl({
      status: "error",
      purpose,
      message: failureMessage(error, "That code was not accepted."),
      returnTo,
    });
  }

  revalidatePath("/security");
  redirect(target);
}

export async function disableMfaAction(formData: FormData) {
  const code = getRequiredField(formData, "code", "authentication code");

  let target: string;

  try {
    await apiMutation<UserMfaStatusPayload>("/session/mfa/disable/", {
      method: "POST",
      body: { code },
    });
    await clearAdminWebMfaCookie();
    target = buildRedirectUrl({ status: "disabled" });
  } catch (error) {
    target = buildRedirectUrl({
      status: "error",
      message: failureMessage(error, "That code was not accepted."),
    });
  }

  revalidatePath("/security");
  redirect(target);
}
