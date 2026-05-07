import { NextRequest, NextResponse } from "next/server";
import { generatePartePdf } from "@/lib/pdf/generatePartePdf";

export async function POST(req: NextRequest) {
  try {
    const { parteId } = await req.json();
    if (!parteId) return NextResponse.json({ error: "parteId required" }, { status: 400 });
    const result = await generatePartePdf(parteId);
    return NextResponse.json(result);
  } catch (err: any) {
    return NextResponse.json({ error: err.message || "Error generating PDF" }, { status: 500 });
  }
}
