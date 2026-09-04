import pickle
import os
import pandas as pd
import plotly.express as px
import plotly.graph_objects as go
from plotly.subplots import make_subplots
from dash import Dash, html, dcc, dash_table, callback, Output, Input
import numpy as np

# Get the directory where this script is located
script_dir = os.path.dirname(os.path.abspath(__file__))

# Load the cleaned findata_tabell.pkl
with open(os.path.join(script_dir, 'findata_tabell_cleaned.pkl'), 'rb') as f:
    findata_tabell_cleaned = pickle.load(f)

# Load cleaned daily streamflow table
with open(os.path.join(script_dir, 'day_streamflow_table_cleaned.pkl'), 'rb') as f:
    day_streamflow = pickle.load(f)

# Load cleaned daily waterlevel table
with open(os.path.join(script_dir, 'day_waterlevel_table_cleaned.pkl'), 'rb') as f:
    day_waterlevel = pickle.load(f)

# Extract each station and its version for the station selection table
station_ids_df = (
    findata_tabell_cleaned[['station_id', 'version']]
    .drop_duplicates()
    .sort_values('station_id')
    .reset_index(drop=True)
)

# Initialize the Dash app
app = Dash(__name__)

DECIMAL_COMMA_TITLE_KEYWORDS = ['vannstand', 'vannforing', 'vannføring', 'vannfaring', 'vannfæring', 'diff']


def has_decimal_comma_keyword(title):
    title_lower = str(title).lower()
    return any(keyword in title_lower for keyword in DECIMAL_COMMA_TITLE_KEYWORDS)


def normalize_station_id(station_id):
    return str(station_id).replace('.', '-')

# Create the app layout
app.layout = html.Div([
    html.H1("DATA HENTET 31.08.2026", style={'textAlign': 'left', 'marginBottom': 30}),

    # Description
        html.Div([
            html.P("Denne appen er utviklet som støtte for kvalitetskontroll av flomtopper basert på fintidsdata.", style={'marginBottom': 10}),
            html.P("Appen viser data for 235 stasjoner som er identifisert som gode kandidater for analyser av flomhendelser med høy tidsoppløsning.", style={'marginBottom': 10}),
            html.P("Tabell 1 viser årlig maksimum vannføring fra hyfin-complete for hver stasjon og hvert år. Når årsflommen er identifisert, hentes tilhørende vannførings- og vannstandsverdier fra flere datakilder for samme stasjon og tidspunkt. Tabellen gjør det dermed mulig å sammenligne verdier fra ulike kilder for den samme hendelsen.", style={'marginBottom': 10}),
            html.P("Tabell 2 viser årlige maksimumsverdier for vannføring basert på både døgnverdier (hydag) og 24 timers glindende midling av findata fra hyfin-complete. Verdiene er sammenstilt per stasjon og år for å gjøre det enkelt å identifisere forskjeller mellom kalendardøgnaggregering og glidende 24 t midling.", style={'marginBottom': 10}),
            html.P("Tabell 3 er bygget opp på samme måte som tabell 2, men viser vannstand i stedet for vannføring.", style={'marginBottom': 10}),
            html.P("Dataene i appen ble sist hentet ut på datoen angitt øverst på siden.", style={'marginBottom': 10}),
        ], style={'backgroundColor': '#f0f0f0', 'padding': 20, 'borderRadius': 5, 'marginTop': 20, 'marginBottom': 20}),

    html.P("Click on a station ID to select it",
           style={'fontStyle': 'italic', 'color': 'gray','marginLeft': '40px'}),
    html.Div([
        dash_table.DataTable(
            id='iqr-table',
            columns=[
                {
                    "name": 'Stasjonsnummer',
                    "id": 'station_id',
                    "type": "text"
                },
                {
                    "name": 'Versjon',
                    "id": 'version',
                    "type": "numeric"
                }
            ],
            data=station_ids_df.to_dict('records'),
            style_table={'overflowX': 'auto', 'overflowY': 'auto', 'maxHeight': '400px', "maxWidth": "300px"},
            style_cell={'textAlign': 'left', 'padding': '10px'},
            style_header={'backgroundColor': 'lightgrey', 'fontWeight': 'bold'},
            style_data_conditional=[
                {
                    'if': {'state': 'selected'},
                    'backgroundColor': 'rgba(0, 116, 217, 0.3)',
                    'border': '1px solid rgb(0, 116, 217)'
                }
            ],
            sort_action='native',
            filter_action='native',
            row_selectable='single',
            selected_rows=[],
            fixed_rows={'headers': True}
        )
    ], style={'marginLeft': '40px', 'marginRight': '40px', 'marginBottom': 24}),

    html.H3(
        "Tabell 1. Vannstand og vannføring, findata - som målt (knekkpunkt)",
        style={'marginTop': 30, 'marginBottom': 12, 'marginLeft': '40px', 'marginRight': '40px'}
    ),

    html.Div([
        dash_table.DataTable(
            id='wl-table',
            columns=[],  # Will be set dynamically
            data=[],
            style_table={'overflowX': 'auto', 'overflowY': 'auto', 'maxHeight': '500px'},
            style_cell={'textAlign': 'left', 'padding': '5px', 'fontSize': 12},
            style_header={
                'backgroundColor': 'lightgrey',
                'fontWeight': 'bold',
                'whiteSpace': 'normal',
                'textAlign': 'center',
                'lineHeight': '18px',
                'height': 'auto',
                'position': 'sticky',
                'top': 0,
                'zIndex': 1,
            },
            style_data_conditional=[]
        )
    ], style={'marginLeft': '40px', 'marginRight': '40px'}),
    html.Div([
        html.H3("Tabell 2. Vannføring, døgnverdier (både kalendardøgn og 24-timers middel)",
                style={'marginTop': 30, 'marginBottom': 12}),
        dash_table.DataTable(
            id='daily-wl-table',
            columns=[],
            data=[],
            style_table={'overflowX': 'auto', 'overflowY': 'auto', 'height': '420px'},
            style_cell={'textAlign': 'left', 'padding': '8px', 'fontSize': 12},
            style_header={
                'backgroundColor': 'lightgrey',
                'fontWeight': 'bold',
                'whiteSpace': 'normal',
                'textAlign': 'center',
                'lineHeight': '18px',
                'height': 'auto',
                'position': 'sticky',
                'top': 0,
                'zIndex': 1,
            }
        )
    ], style={'marginLeft': '40px', 'marginRight': '40px', 'marginBottom': 24}),
    html.Div([
        html.H3("Tabell 3. Vannstand, døgnverdier (både kalendardøgn og 24-timers middel)",
                style={'marginTop': 30, 'marginBottom': 12}),
        dash_table.DataTable(
            id='daily-waterlevel-table',
            columns=[],
            data=[],
            style_table={'overflowX': 'auto', 'overflowY': 'auto', 'height': '420px'},
            style_cell={'textAlign': 'left', 'padding': '8px', 'fontSize': 12},
            style_header={
                'backgroundColor': 'lightgrey',
                'fontWeight': 'bold',
                'whiteSpace': 'normal',
                'textAlign': 'center',
                'lineHeight': '18px',
                'height': 'auto',
                'position': 'sticky',
                'top': 0,
                'zIndex': 1,
            }
        )
    ], style={'marginLeft': '40px', 'marginRight': '40px', 'marginBottom': 24}),
], style={'padding': '20px 0px'})

from dash.dependencies import Output, Input
from dash.dependencies import State

@app.callback(
    [Output('wl-table', 'columns'),
     Output('wl-table', 'data'),
        Output('wl-table', 'style_data_conditional'),
     Output('daily-wl-table', 'columns'),
        Output('daily-wl-table', 'data'),
        Output('daily-waterlevel-table', 'columns'),
        Output('daily-waterlevel-table', 'data')],
    [Input('iqr-table', 'selected_rows'),
     Input('iqr-table', 'data')]
)
def update_plots(selected_rows, table_data):
    def format_decimal_comma(value):
        if pd.isna(value):
            return None
        return str(value).replace('.', ',')

    def format_columns_by_display_name(dataframe, display_names):
        for col in dataframe.columns:
            display_title = display_names.get(col, col)
            if has_decimal_comma_keyword(display_title):
                dataframe[col] = dataframe[col].map(format_decimal_comma)

    if not selected_rows or len(selected_rows) == 0:
        # Return empty data with message
        return [], [], [], [], [], [], []

    # Only one station can be selected
    selected_station_idx = selected_rows[0]
    selected_station_id = table_data[selected_station_idx]['station_id']

    # --- Filter and display full_wl_discharge_table for selected station ---
    fin_station = findata_tabell_cleaned[findata_tabell_cleaned['station_id'] == selected_station_id].copy()
    display_cols = [
        'hyfinc_datetime',
        'hyfinc_vannfring',
        'hykval_vannfring',
        'hyfinc_vannstand',
        'hykval_vannstand',
        'percent_diff_hyfinc_hykval'
    ]
    display_names = {
        'hyfinc_datetime': 'date - time hyfinc AM',
        'hyfinc_vannfring': 'hyfin-c vannføring',
        'hykval_vannfring': 'hykval vannføring',
        'hyfinc_vannstand': 'hyfin-c vannstand',
        'hykval_vannstand': 'hykval vannstand',
        'percent_diff_hyfinc_hykval': '% diff, vannføring'
    }
    # Only keep and order the specified columns if they exist
    changed_rows = fin_station['changed'].fillna(False).astype(bool).tolist()
    fin_station = fin_station[[col for col in display_cols if col in fin_station.columns]]
    # Format datetime column if present
    if 'hyfinc_datetime' in fin_station.columns:
        fin_station['hyfinc_datetime'] = pd.to_datetime(fin_station['hyfinc_datetime'], errors='coerce').dt.strftime('%d.%m.%Y %H:%M:%S')
    format_columns_by_display_name(fin_station, display_names)
    if not fin_station.empty:
        wl_columns = [
            {
                "name": display_names.get(i, i),
                "id": i
            }
            for i in fin_station.columns
        ]
        wl_data = fin_station.to_dict('records')
        wl_style_data_conditional = [
            {
                'if': {'row_index': row_index},
                'backgroundColor': '#f8d7da',
                'color': '#842029'
            }
            for row_index, changed in enumerate(changed_rows)
            if changed
        ]
    else:
        wl_columns = []
        wl_data = []
        wl_style_data_conditional = []

    # --- Filter and display daily streamflow for selected station ---
    daily_station = day_streamflow[
        day_streamflow['station_id'].map(normalize_station_id) == normalize_station_id(selected_station_id)
    ].copy()
    daily_station = daily_station.sort_values('year') if 'year' in daily_station.columns else daily_station
    daily_display_cols = [
        'year',
        'hydag_datetime',
        'hydag_vannfring',
        'hykval_kalendardgn_vannfring',
        'hyfinc_24t_datetime',
        'hyfinc_24t_vannfring',
        'hykval_24t_vannfring'
    ]
    daily_display_names = {
        'year': 'år',
        'hydag_datetime': 'dato - tid hydag AM',
        'hydag_vannfring': 'hydag vannføring',
        'hykval_kalendardgn_vannfring': 'hykval (kalendardøgn) vannføring',
        'hyfinc_24t_datetime': 'dato - tid hyfin-c 24t AM',
        'hyfinc_24t_vannfring': 'hyfin-c 24t vannføring',
        'hykval_24t_vannfring': 'hykval (24t) vannføring'
    }
    daily_station = daily_station[[c for c in daily_display_cols if c in daily_station.columns]]
    for dt_col in ['hydag_datetime', 'hyfinc_24t_datetime']:
        if dt_col in daily_station.columns:
            daily_station[dt_col] = pd.to_datetime(
                daily_station[dt_col], format='%Y%m%d/%H%M', errors='coerce'
            ).dt.strftime('%d.%m.%Y %H:%M:%S')
    format_columns_by_display_name(daily_station, daily_display_names)
    if not daily_station.empty:
        daily_columns = [{"name": daily_display_names.get(i, i), "id": i} for i in daily_station.columns]
        daily_data = daily_station.to_dict('records')
    else:
        daily_columns = []
        daily_data = []

    # --- Filter and display daily water level for selected station ---
    daily_waterlevel_station = day_waterlevel[
        day_waterlevel['station_id'].map(normalize_station_id) == normalize_station_id(selected_station_id)
    ].copy()
    daily_waterlevel_station = (
        daily_waterlevel_station.sort_values('year')
        if 'year' in daily_waterlevel_station.columns
        else daily_waterlevel_station
    )
    daily_waterlevel_display_cols = [
        'year',
        'hydag_datetime',
        'hydag_vannstand',
        'hykval_kalendardgn_vannstand',
        'hyfinc_24t_datetime',
        'hyfinc_24t_vannstand',
        'hykval_24t_vannstand'
    ]
    daily_waterlevel_display_names = {
        'year': 'år',
        'hydag_datetime': 'dato - tid hydag AM',
        'hydag_vannstand': 'hydag vannstand',
        'hykval_kalendardgn_vannstand': 'hykval (kalendardøgn) vannstand',
        'hyfinc_24t_datetime': 'dato - tid hyfin-c 24t AM',
        'hyfinc_24t_vannstand': 'hyfin-c 24t vannstand',
        'hykval_24t_vannstand': 'hykval (24t) vannstand'
    }
    daily_waterlevel_station = daily_waterlevel_station[
        [c for c in daily_waterlevel_display_cols if c in daily_waterlevel_station.columns]
    ]
    for dt_col in ['hydag_datetime', 'hyfinc_24t_datetime']:
        if dt_col in daily_waterlevel_station.columns:
            daily_waterlevel_station[dt_col] = pd.to_datetime(
                daily_waterlevel_station[dt_col], format='%Y%m%d/%H%M', errors='coerce'
            ).dt.strftime('%d.%m.%Y %H:%M:%S')
    format_columns_by_display_name(daily_waterlevel_station, daily_waterlevel_display_names)
    if not daily_waterlevel_station.empty:
        daily_waterlevel_columns = [
            {"name": daily_waterlevel_display_names.get(i, i), "id": i}
            for i in daily_waterlevel_station.columns
        ]
        daily_waterlevel_data = daily_waterlevel_station.to_dict('records')
    else:
        daily_waterlevel_columns = []
        daily_waterlevel_data = []

    return (
        wl_columns,
        wl_data,
        wl_style_data_conditional,
        daily_columns,
        daily_data,
        daily_waterlevel_columns,
        daily_waterlevel_data
    )

if __name__ == '__main__':
    app.run(debug=True, port=8050)
