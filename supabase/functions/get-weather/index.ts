import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

/**
 * get-weather
 *
 * Lightweight "is it raining here RIGHT NOW?" lookup for the map rain effect.
 * Holds the WeatherAPI.com key server-side (Supabase secret `weather_api`) so
 * it never ships in the app. Requires an authenticated caller to prevent quota
 * abuse. Fails SOFT: any error -> { raining: false } so the map never breaks.
 *
 * Request:  POST { lat: number, lng: number }
 * Response: { raining: boolean, precip_mm, condition, code, is_day, temp_c }
 *
 * Accuracy model (tuned to STOP false "it's raining" on dry grey days):
 *   WeatherAPI liberally reports light/patchy/"possible" rain codes on overcast
 *   but DRY days, and keeps a nonzero precip_mm for a while AFTER rain stops.
 *   So NEITHER the code alone NOR precip alone is trustworthy at the light end.
 *   We therefore split codes into two tiers:
 *     - DEFINITE_RAIN: moderate-or-heavier / showers / thunder-with-rain. Heavy
 *       enough that the condition code alone is trusted.
 *     - NEEDS_PRECIP: light / patchy / drizzle / "possible" / intermittent
 *       ("...at times"). Counted as rain ONLY when real precipitation
 *       corroborates the code (precip_mm >= threshold). This is the whole fix:
 *       a "Light rain"/"Patchy light rain" code with precip_mm 0 is treated as
 *       NOT raining.
 */

// Trust the code alone: moderate rain and up, heavy showers, thunder-with-rain.
const DEFINITE_RAIN = new Set<number>([
    1171, // Heavy freezing drizzle
    1189, // Moderate rain
    1192, // Heavy rain at times
    1195, // Heavy rain
    1201, // Moderate or heavy freezing rain
    1243, // Moderate or heavy rain shower
    1246, // Torrential rain shower
    1276, // Moderate or heavy rain with thunder
])

// Light / patchy / drizzle / "possible" / intermittent. Only counts as rain
// when precipitation actually backs the code up — these fire constantly on dry
// overcast days otherwise.
const NEEDS_PRECIP = new Set<number>([
    1063, // Patchy rain possible
    1072, // Patchy freezing drizzle possible
    1150, // Patchy light drizzle
    1153, // Light drizzle
    1168, // Freezing drizzle
    1180, // Patchy light rain
    1183, // Light rain
    1186, // Moderate rain at times
    1198, // Light freezing rain
    1240, // Light rain shower
    1273, // Patchy light rain with thunder
])

// mm needed to confirm a NEEDS_PRECIP code. Set above the trace amount
// WeatherAPI keeps reporting for a while after rain has already stopped.
const PRECIP_CORROBORATION_MM = 0.2

serve(async (req: Request) => {
    if (req.method === 'OPTIONS') {
        return new Response('ok', { headers: corsHeaders })
    }

    try {
        const weatherKey = Deno.env.get('weather_api')
        if (!weatherKey) throw new Error('Missing weather_api secret')

        // Auth: only signed-in users may call (protects the WeatherAPI quota).
        const sbUrl = Deno.env.get('SUPABASE_URL') ?? ''
        const sbAnonKey = Deno.env.get('SUPABASE_ANON_KEY') ?? ''
        const supabaseClient = createClient(sbUrl, sbAnonKey, {
            global: { headers: { Authorization: req.headers.get('Authorization')! } },
        })
        const { data: { user } } = await supabaseClient.auth.getUser()
        if (!user) {
            return new Response(JSON.stringify({ error: 'Unauthorized' }), {
                headers: { ...corsHeaders, 'Content-Type': 'application/json' },
                status: 401,
            })
        }

        const { lat, lng } = await req.json()
        if (typeof lat !== 'number' || typeof lng !== 'number') {
            return new Response(JSON.stringify({ error: 'Missing or invalid lat/lng' }), {
                headers: { ...corsHeaders, 'Content-Type': 'application/json' },
                status: 400,
            })
        }

        const url =
            `https://api.weatherapi.com/v1/current.json?key=${weatherKey}` +
            `&q=${lat},${lng}&aqi=no`

        const resp = await fetch(url)
        if (!resp.ok) {
            const body = await resp.text()
            console.error(`WeatherAPI error ${resp.status}: ${body}`)
            // Fail soft - no rain rather than an error.
            return new Response(
                JSON.stringify({ raining: false, error: 'weather_unavailable' }),
                {
                    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
                    status: 200,
                },
            )
        }

        const data = await resp.json()
        const cur = data.current ?? {}
        const code: number | undefined = cur.condition?.code
        const precip: number = typeof cur.precip_mm === 'number' ? cur.precip_mm : 0

        const definite = code !== undefined && DEFINITE_RAIN.has(code)
        const lightConfirmed =
            code !== undefined && NEEDS_PRECIP.has(code) && precip >= PRECIP_CORROBORATION_MM

        // Heavy code -> trust it. Light/patchy code -> only if precip backs it up.
        // A dry code (or a light code with no precip) is NOT raining.
        const raining = definite || lightConfirmed

        return new Response(
            JSON.stringify({
                raining,
                precip_mm: precip,
                condition: cur.condition?.text ?? null,
                code: code ?? null,
                is_day: cur.is_day ?? null,
                temp_c: cur.temp_c ?? null,
            }),
            {
                headers: { ...corsHeaders, 'Content-Type': 'application/json' },
                status: 200,
            },
        )
    } catch (error: any) {
        console.error('get-weather error:', error)
        // Fail soft so the map never breaks on weather issues.
        return new Response(
            JSON.stringify({ raining: false, error: error?.message ?? 'unknown' }),
            {
                headers: { ...corsHeaders, 'Content-Type': 'application/json' },
                status: 200,
            },
        )
    }
})
