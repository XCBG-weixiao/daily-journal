import { redirect } from "next/navigation";
import { localDate } from "@/lib/content/dates";
export default function Home() {
  const today = localDate();
  redirect(`/calendar?month=${today.slice(0, 7)}&date=${today}`);
}
