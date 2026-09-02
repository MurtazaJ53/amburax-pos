import { AuthResetPassword } from "@/components/auth-reset-password";

export const metadata = {
  title: "Reset Password | Business Hub Cloud",
  description: "Choose a new password using the link from your reset email",
};

/**
 * The page the emailed link lands on: /reset-password?token=...
 *
 * The token is read here, on the server, and passed down as a prop. It is
 * never put in a cookie or in storage - it is a one-use credential that
 * belongs in the request that spends it and nowhere else.
 */
export default async function ResetPasswordPage({
  searchParams,
}: {
  searchParams: Promise<{ token?: string }>;
}) {
  const { token } = await searchParams;
  return <AuthResetPassword token={(token || "").trim()} />;
}
