import { AuthLogin } from "@/components/auth-login";

export const metadata = {
  title: "Create a shop | Business Hub Cloud",
  description: "Create a Business Hub shop and start selling",
};

/**
 * The real sign-up, not a second one.
 *
 * This route used to render its own two-step form. It collected a name, an
 * email, a phone number and a password, and then called nothing at all -
 * `handleFinishRegister` pushed straight to /pos, which bounced back to
 * /login because no account had been created. Anybody who landed here could
 * not sign up, and nothing said why.
 *
 * Two sign-up flows is how one of them ends up broken. There is one now, and
 * this route opens it on the right panel.
 */
export default function RegisterPage() {
  return <AuthLogin initialMode="register" />;
}
