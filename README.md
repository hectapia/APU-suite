# APU-suite

Unitary Price Analysis (*Análisis de Precios Unitarios - APU*) and cost engineering platform for public and private procurement tenders, built according to Mexican procurement standards (PEMEX LOPSRM).

## Features

- **Tender Dashboard**: Grid of event cards showing real-time progress for services and direct catalog supplies.
- **Dual Pricing Workflows**:
  - **Services (`concept_unit = 'SERVICIO'`)**: Bottom-up APU analysis compiling Materials, Labor Crews (with performance yield), Equipment Sets (with hourly yield), and Safety/Tools, followed by indirects, financing, utility, and SFP 5 al millar.
  - **Direct Parts (`concept_unit <> 'SERVICIO'`)**: Direct unit price assignment for commercial supplies (`PIEZA`, `JUEGO`, `METRO`, etc.).
- **Secure Access**: Tokenized magic link invitations for contractors to access assigned tenders.
- **Fast Concept Search**: Sub-second full-text and trigram search across 1,300+ concept items.

## Tech Stack

- **Frontend**: Next.js 15 (App Router), React 19, TypeScript, Tailwind CSS, Shadcn UI
- **Database & Auth**: PostgreSQL 16 on Supabase with Row Level Security (RLS)
- **Virtualization**: TanStack Table for large concept catalogs

## Getting Started

### 1. Database Setup
1. Create a project in [Supabase](https://supabase.com).
2. Open the **SQL Editor** in your Supabase dashboard.
3. Paste and run `supabase_setup_and_seed.sql`.


### 2. Run the Application
```bash
npm install
npm run dev
```

Open [http://localhost:3000](http://localhost:3000) to access the application.
