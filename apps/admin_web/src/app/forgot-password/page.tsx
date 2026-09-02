import { AuthForgotPassword } from "@/components/auth-forgot-password";

export const metadata = {
  title: "Forgot Password | Business Hub Cloud",
  description: "Ask for a link to choose a new Business Hub password",
};

export default function ForgotPasswordPage() {
  return <AuthForgotPassword />;
}
