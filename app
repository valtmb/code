import pandas as pd
import dash
import dash_html_components as html
import dash_core_components as dcc # Lib, kuriame duoda grafikams interaktyvumo ir funkcionalumo
import plotly.express as px # supaprastina grafiku kurima (bet maziau funkcionalumo duoda)
import plotly.graph_objects as go
from dash.dependencies import Input, Output #Pasiema komponento id
import dash_bootstrap_components as dbc
import pyodbc
import keyring
import dash_table
import time

# Duomenu uzkrovimas
#------------------------------------------------
conn = pyodbc.connect('Driver={SQL Server};'
                      'Server=HTIC-SQL-ROBOT;'
                      'UID=skaitytojas;'
                      'PWD=' + keyring.get_password("database", "skaitytojas") + ';'
                      'Database=UiPath;'
                      'Trusted_Connection=No;')

cursor = conn.cursor()
#Lenteles duomenys
runningData = pd.read_sql_query('''Select Dateadd(hour, 3, Cast(JB.StartTime AS datetime2)) As StartingTime,RL.Name, JB.State, JB.Info, DATEDIFF(minute, Dateadd(hour, 3, Cast(JB.StartTime AS datetime2)), SYSDATETIME()) as RunningTime
From [UiPath].[dbo].[Jobs] as JB
INNER JOIN [UiPath].[dbo].[Releases] AS RL ON RL.Id = JB.ReleaseId
WHERE JB.TenantId = 3 and JB.HostMachineName LIKE 'VTIC-ESO-ROBOT%' and JB.State = 1''', conn)
#Vakaryksciai duomenys
yesterdayData = pd.read_sql_query('''Select QD.Name, cast(QI.EndProcessing AS Date) as Date,
sum(case when QI.ProcessingExceptionType=0 then 1 else 0 end) as TotalApplicationExceptions,
sum(case when QI.ProcessingExceptionType=1 then 1 else 0 end) as TotalBusinessExceptions
From [UiPath].[dbo].[QueueItems] as QI
INNER JOIN [UiPath].[dbo].[QueueDefinitions] AS QD ON QD.Id = QI.[QueueDefinitionId]
WHERE  QI.TenantId = 3 and  QI.Status = 2 AND QD.IsDeleted = 0 and DATEDIFF(day, QI.EndProcessing, GETDATE()) = 1
Group by QD.Name, cast(QI.EndProcessing AS Date)
Order by cast(QI.EndProcessing AS Date)''', conn)
#Siandienos duomenys
todaysData = pd.read_sql_query('''Select QD.Name, cast(QI.EndProcessing AS Date) as Date,
sum(case when QI.ProcessingExceptionType=0 then 1 else 0 end) as TotalApplicationExceptions,
sum(case when QI.ProcessingExceptionType=1 then 1 else 0 end) as TotalBusinessExceptions
From [UiPath].[dbo].[QueueItems] as QI
INNER JOIN [UiPath].[dbo].[QueueDefinitions] AS QD ON QD.Id = QI.[QueueDefinitionId]
WHERE  QI.TenantId = 3 and  QI.Status = 2 AND QD.IsDeleted = 0 and cast(QI.EndProcessing as Date) = cast(getdate() as Date)
Group by QD.Name, cast(QI.EndProcessing AS Date)
Order by cast(QI.EndProcessing AS Date)''', conn)
#Svaites duomenys
df = pd.read_sql_query('''Select QD.Name, cast(QI.EndProcessing AS Date) as Date, sum(case when QI.ProcessingExceptionType=0 then 1 else 0 end) as TotalApplicationExceptions, sum(case when QI.ProcessingExceptionType=1 then 1 else 0 end) as TotalBusinessExceptions From [UiPath].[dbo].[QueueItems] as QI INNER JOIN [UiPath].[dbo].[QueueDefinitions] AS QD ON QD.Id = QI.[QueueDefinitionId] WHERE  QI.TenantId = 3 and  QI.Status = 2 AND QD.IsDeleted = 0 and QI.EndProcessing Between Convert(datetime, '2021-05-01') and CONVERT(datetime, '2021-05-16 23:59:59:999') Group by QD.Name, cast(QI.EndProcessing AS Date) Order by cast(QI.EndProcessing AS Date)''', conn)
df.index = pd.to_datetime(df['Date'])
# Programos init lygis (paleidimas)
app = dash.Dash(__name__)
#server = app.server


def get_options (list_names):
    dict_list = []
    for i in list_names:
        dict_list.append({'label': i, 'value':i})
    
    return dict_list 

card1_body = dbc.CardBody([html.H4("Pavadinimas", className="card-title",id="card_num1"),
                  html.P("Klaidų kiekis šiandien", className="card-text",id="card_text1")
                 ],
                 style={'display': 'inline-block',
                        'text-align': 'center',
                        'color':'white',
                        'background-color': 'rgba(37, 150, 190)'})

card2_body = dbc.CardBody([html.H4("Pavadinimas", className="card-title",id="card_num2"),
                  html.P("Klaidų kiekis vakar", className="card-text",id="card_text2")
                 ],
                 style={'display': 'inline-block',
                        'text-align': 'center',
                        'color':'white',
                        'background-color': 'rgba(37, 150, 190)'})

card1 = dbc.Card(card1_body,outline=True)
card2 = dbc.Card(card2_body,outline=True)

PAGE_SIZE = 9


# Programos aprasymo lygis
app.layout = html.Div(children=[
    dcc.Location(id='url', refresh=False),
    html.Div(id='page-content'),
    dcc.ConfirmDialog(id='confirm',
                      message ='Pasiektas leistinas klaidų skaičius'),
    html.Div(className='row',
             children=[
                 html.Div(className='four columns div-user-controls',
                          children=[
                              dcc.Link(html.Button('Registruoti gedimą'), href='https://form.jotform.com/211294196393360', target='_blank'),
                              html.H2('Dash - Robotų transakcijos'),
                              html.P('Pasirinkite viena ar kelis robotus.'),
                               html.Div(
                                  className='div-for-dropdown',
                                       children=[
                                           dcc.Dropdown(id='robotselector',
                                                        options=get_options(df['Name'].unique()),
                                                        multi=True,
                                                        value=[df['Name'].sort_values()[0]],
                                                        style={'backgroundColor': 'black'},
                                                        className='robotselector')
                                           ],
                                       style={'color':'black'}),
                                    html.Div(
                                        className='div-for-card',
                                            children=[
                                                 dbc.Row(id="card_row",children=[dbc.Col(card1)
                                                        ])]
                                                         
                                        ),
                                    html.Div(
                                        className='div-for-dropdown',
                                            children=[
                                           dcc.Dropdown(id='robotselector1',
                                                        options=get_options(todaysData['Name'].unique()),
                                                        multi=False,
                                                        value=[todaysData['Name'].sort_values()[0]],
                                                        style={'backgroundColor': 'black'},

                                                        className='robotselector1')
                                           ],
                                       style={'color':'black'}),
                                    
                                     html.Div(
                                          className = 'div-for-card',
                                            children=[
                                               dbc.Row(id='card_row1', children=[dbc.Col(card2)
                                                        ])]
                                           ),
                                     html.Div(
                                         className='div-for-dropdown',
                                         children=[
                                             dcc.Dropdown(id='robotselector2',
                                                          options=get_options(yesterdayData['Name'].unique()),
                                                          multi=False,
                                                          value=[yesterdayData['Name'].sort_values()[0]],
                                                          style={'backgroundColor':'black'},
                                                          className='robotselector2')
                                             ],
                                         style={'color':'black'}),
                              ]
                          ),
               
                                 
                 html.Div(className='eight columns div-for-charts bg-grey',
                          children=[
                              dcc.Graph(id='timeseries', config={'displayModeBar': False}),
                              
                html.Div([dash_table.DataTable(
                    id='table-multicol-sorting',
                    columns=[
                        {"name": i, "id": i} for i in sorted(runningData.columns)
                        ],
                    style_header={'backgroundColor': 'rgb(30, 30, 30)'},
                    style_cell={
                            'textAlign':'left',
                            'backgroundColor': 'rgb(50, 50, 50)',
                            'color': 'white'
                            },
                    page_current=0,
                    page_size=PAGE_SIZE,
                    page_action='custom',
                    
                    sort_action='custom',
                    sort_mode='multi',
                    sort_by=[]
                    )])
                             ]),
                   
                
                 ])
    ])




@app.callback(Output('timeseries', 'figure'),
              [Input('robotselector', 'value')]
              )
def update_timeseries(selected_dropdown_value):

    trace = []  
    df_sub = df
 
    for Name in selected_dropdown_value:   
        trace.append(go.Scatter(x=df_sub[df_sub['Name'] == Name].index,
                                 y=df_sub[df_sub['Name'] == Name]['TotalApplicationExceptions'],
                                 mode='lines',
                                 opacity=1,
                                 name=Name,
                                 textposition='bottom center'))  
    traces = [trace]
    data = [val for sublist in traces for val in sublist]
    figure = {'data': data,
              'layout': go.Layout(
                  colorway=["#5E0DAC", '#FF4F00', '#375CB1', '#FF7400', '#FFF400', '#FF0056'],
                  template='plotly_dark',
                  paper_bgcolor='rgba(0, 0, 0, 0)',
                  plot_bgcolor='rgba(0, 0, 0, 0)',
                  margin={'b': 15},
                  hovermode='x',
                  autosize=True,
                  title={'text': 'Robotų transakcijos', 'font': {'color': 'white'}, 'x': 0.5},
                  xaxis={'range': [df_sub.index.min(0), df_sub.index.max(0)]},
              ),

              }

    return figure
@app.callback(Output('confirm', 'displayed'),
              Input('robotselector1','value')
              )

def display_confirm(value):
    name_df2 = todaysData[(todaysData.Name==value)]
    tot_app2 = f"{name_df2['TotalApplicationExceptions'].sum():,.0f}"
    #display = dcc.ConfirmDialog(id='confirm',
        #message='Procesas {name_df2} viršyjo leistiną klaidų skaičių:{tot_app2}')
    if int(tot_app2) > 0:
        time.sleep(1)
        return True


@app.callback(Output('card_row','children'),
             [Input('robotselector1', 'value')]
             )

def update_cardsToday (dropdown_value):
    name_df = todaysData[(todaysData.Name==dropdown_value)]
    tot_app = f"{name_df['TotalApplicationExceptions'].sum():,.0f}"
    
    card1 = dbc.Card([
        dbc.CardHeader("Šiandienos klaidų kiekis"),
        dbc.CardBody([
            html.H4(tot_app, className='card-title'),
            html.P(f"Procesas:{dropdown_value}")
            ])
        ],
        style={'display': 'inline-block',
           'width': '100%',
           'text-align': 'center',
           'background-color': 'rgba(37, 150, 190)',
           'color':'white',
           'fontWeight': 'bold',
           'fontSize':20},
    outline=True)
    return (card1)

@app.callback(Output('card_row1', 'children'),
              [Input('robotselector2', 'value')]
              )
def update_cardsYesterday (dropdown_value1):
    name1_df = yesterdayData[(yesterdayData.Name==dropdown_value1)]
    tot1_app = f"{name1_df['TotalApplicationExceptions'].sum():,.0f}"
    
    card2 = dbc.Card([
        dbc.CardHeader("Vakarykštės dienos klaidų kiekis"),
        dbc.CardBody([
            html.H4(tot1_app, className='card-title'),
            html.P(f"Procesas:{dropdown_value1}")
            ])
        ],
        style={'display': 'inline-block',
           'width': '100%',
           'text-align': 'center',
           'background-color': 'rgba(37, 150, 190)',
           'color':'white',
           'fontWeight': 'bold',
           'fontSize':20},
    outline=True)
    return (card2)

@app.callback(
    Output('table-multicol-sorting', "data"),
    Input('table-multicol-sorting', "page_current"),
    Input('table-multicol-sorting', "page_size"),
    Input('table-multicol-sorting', "sort_by"))
def update_table(page_current, page_size, sort_by):
    print(sort_by)
    if len(sort_by):
        dff = runningData.sort_values(
            [col['column_id'] for col in sort_by],
            ascending=[
                col['direction'] == 'asc'
                for col in sort_by
            ],
            inplace=False
        )
    else:
        dff = runningData

    return dff.iloc[
        page_current*page_size:(page_current+ 1)*page_size
    ].to_dict('records')
    
# Paleisti programa
if __name__ == '__main__':
    app.run_server(debug=True)
