import streamlit as st
import pandas as pd
import matplotlib.pyplot as plt
import plotly.express as px
from data_loader import (
    get_filter_options, 
    get_severity_breakdown, 
    get_transport_mode_distribution, 
    get_borough_summary, 
    get_monthly_trends, 
    get_top_accident_prone_streets, 
    get_accident_locations, 
    get_weather_accident_trends,
    get_weekday_vs_weekend_trends,
    get_high_risk_days,
    get_accidents_by_age_group,
    get_fatalities_by_age 
)
from streamlit_folium import folium_static
from folium.plugins import HeatMap
import folium

# ✅ Set Wide Layout & Theme
st.set_page_config(
    page_title="🚦 London Traffic Accidents Dashboard",
    layout="wide",
    initial_sidebar_state="expanded"
)

# ✅ Custom CSS Styling
st.markdown("""
    <style>
        .main { background-color: #F5F5F5; }
        h1, h2, h3 { color: #333333; font-family: Arial, sans-serif; }
        .css-1d391kg { padding: 20px; } /* Adds spacing around sections */
        .stDataFrame { background-color: white; } /* Table styling */
        .sidebar .sidebar-content { background-color: #F0F0F0; } /* Sidebar styling */
    </style>
""", unsafe_allow_html=True)

# ✅ Sidebar with Icons
st.sidebar.title("🔍 Filter Accidents")
st.sidebar.markdown("---")

# ✅ Reset Filters Button
if st.sidebar.button("🔄 Reset Filters"):
    st.experimental_rerun()


# ✅ Load filter options
filter_data = get_filter_options()

# ✅ Sidebar Title
st.sidebar.title("🔍 Filter Accidents")

# ✅ Year Filter
year_options = ["All Years"] + sorted(filter_data["year"].dropna().astype(int).unique(), reverse=True)
selected_year = st.sidebar.selectbox("Select Year", year_options)

# ✅ Borough Filter
borough_options = ["All"] + sorted(filter_data["borough"].dropna().unique())
selected_borough = st.sidebar.selectbox("Select Borough", borough_options)

# ✅ Severity Filter
severity_options = ["All"] + sorted(filter_data["accident_severity"].dropna().unique())
selected_severity = st.sidebar.selectbox("Select Severity", severity_options)



# ✅ Apply Filters to Queries
filters = []
if selected_year != "All Years":
    filters.append(f"EXTRACT(YEAR FROM accident_date) = {selected_year}")
if selected_borough != "All":
    filters.append(f"borough = '{selected_borough}'")
if selected_severity != "All":
    filters.append(f"accident_severity = '{selected_severity}'")


# ✅ Combine Filters into a WHERE Clause
where_clause = "WHERE " + " AND ".join(filters) if filters else ""


# Display monthly trends
df_monthly_trends = get_monthly_trends(where_clause)
if selected_year != "All Years":
    st.subheader(f"Monthly Accident Trends in {selected_year}")
else:
    st.subheader("Monthly Accident Trends (All Years Combined)")

if not df_monthly_trends.empty:
    fig_monthly = px.line(df_monthly_trends, 
                          x="month_name", 
                          y="accident_count", 
                          title="Monthly Accident Trends",
                          labels={"month_name": "Month", "accident_count": "Accident Count"},
                          width=0,
                          height=500)
    st.plotly_chart(fig_monthly, use_container_width=True)
else:
    st.warning("No monthly data available.")

# ✅ Display Borough-Wise Summary Only When "All" Boroughs Are Selected
if selected_borough == "All":
    df_borough = get_borough_summary(where_clause)
    df_borough.reset_index(drop=True, inplace=True)
    df_borough.index += 1

    st.subheader("Borough-Wise Accident Summary")
    if not df_borough.empty:
        st.dataframe(df_borough.style.format({
            "total_accidents": "{:,}",
            "slight_accidents": "{:,}",
            "serious_accidents": "{:,}",
            "fatal_accidents": "{:,}"
        }))
    else:
        st.warning("No accident data available for selected filters.")


# ✅ Fetch filtered data
df_severity = get_severity_breakdown(where_clause)
df_transport = get_transport_mode_distribution(where_clause)

st.subheader("Accident Breakdown")

col1, col2 = st.columns([4, 4])

# ✅ Severity Breakdown Pie Chart (Interactive)
with col1:
    st.subheader("Severity Breakdown")
    if not df_severity.empty:
        fig_severity = px.pie(df_severity, 
                               names="accident_severity", 
                               values="count",
                               title="Accident Severity Distribution",
                               color_discrete_sequence=px.colors.qualitative.Set2,
                               hole=0.3,
                               width=600,  
                               height=500)  
        fig_severity.update_traces(textinfo="percent+label")
        st.plotly_chart(fig_severity, use_container_width=True)
    else:
        st.warning("No severity data available.")


with col2:
    # ✅ Fetch Weather-Based Accident Data
    df_weather = get_weather_accident_trends(where_clause)

    st.subheader("🌦️ Impact of Weather on Accidents")

    if not df_weather.empty:
        fig_weather = px.pie(df_weather, 
                            names="weather_category", 
                            values="accident_count",
                            title="Accidents by Weather Condition",
                            color_discrete_sequence=px.colors.qualitative.Set2,
                            hole=0.3,  # Creates a donut-style pie chart
                            width=600,
                            height=500)
        fig_weather.update_traces(textinfo="percent+label")
        st.plotly_chart(fig_weather, use_container_width=True)
    else:
        st.warning("No weather accident data available.")

# ✅ Fetch Weather vs. Severity Breakdown
df_weather_severity = get_weather_accident_trends(where_clause, by_severity=True)
st.subheader("🌦️ Weather vs. Severity Breakdown")

if not df_weather_severity.empty:
    fig_weather_severity = px.bar(df_weather_severity, 
                                  x="weather_category", 
                                  y="accident_count",
                                  color="accident_severity",
                                  title="Accident Severity by Weather Condition",
                                  barmode="stack",  # ✅ Stacked bar chart
                                  color_discrete_sequence=px.colors.qualitative.Set2,
                                  labels={"accident_count": "Number of Accidents", "weather_category": "Weather Condition"})
    
    st.plotly_chart(fig_weather_severity, use_container_width=True)
else:
    st.warning("No weather severity data available.")


# ✅ Display Top 10 Accident-Prone Streets
st.subheader(" Top 10 Accident-Prone Streets")
df_top_streets = get_top_accident_prone_streets()
if not df_top_streets.empty:
    df_top_streets.reset_index(drop=True, inplace=True)
    df_top_streets.index += 1
    st.dataframe(df_top_streets.style.format({"accident_count": "{:,}"}))
else:
    st.warning("No data available for top accident-prone streets.")

# ✅ Fetch accident locations & total count
result = get_accident_locations(where_clause)

# ✅ Unpack safely to avoid errors
if isinstance(result, tuple) and len(result) == 2:
    df_locations, total_accidents = result
else:
    df_locations, total_accidents = pd.DataFrame(), 0  # Prevents crash if function fails

st.subheader("🔥 Accident Density Heatmap")

if not df_locations.empty:
    # ✅ Dynamically Adjust Radius Based on Data Size
    if total_accidents < 1000:
        radius = 5
    elif total_accidents < 5000:
        radius = 8
    else:
        radius = 12  # For very large datasets
    
    m = folium.Map(location=[51.5074, -0.1278], zoom_start=11, tiles="cartodbpositron")

    # ✅ Convert DataFrame to List of [lat, lon] Pairs
    heat_data = df_locations[["latitude", "longitude"]].values.tolist()

    # ✅ Apply Scaling to Intensity
    HeatMap(heat_data, radius=radius, blur=15, min_opacity=0.2).add_to(m)

    folium_static(m, width=1200, height=850)
else:
    st.warning("No accident location data available for selected filters.")


st.subheader("Transport Mode Breakdown")
if not df_transport.empty:
    fig_transport = px.pie(df_transport, 
                            names="vehicle_type", 
                            values="count",
                            title="Accidents by Transport Mode",
                            color_discrete_sequence=px.colors.qualitative.Pastel,
                            hole=0.2,
                            width=1000,  
                            height=750)  
    fig_transport.update_traces(textinfo="percent+label")
    st.plotly_chart(fig_transport, use_container_width=True)
else:
    st.warning("No transport mode data available.")


# ✅ Fetch Weekday vs. Weekend Trends
df_weekday_weekend = get_weekday_vs_weekend_trends(where_clause)
df_high_risk_days = get_high_risk_days(where_clause)

st.subheader("High-Risk Days & Weekday vs. Weekend Trends")

if not df_weekday_weekend.empty:
    col1, col2 = st.columns([3, 2])

    with col1:
        st.write("Comparison of accident occurrences between weekdays and weekends.")

        # ✅ Display Bar Chart
        fig_weekday_weekend = px.bar(
            df_weekday_weekend,
            x="day_type",
            y="accident_count",
            title="Accidents: Weekdays vs. Weekends",
            labels={"accident_count": "Number of Accidents", "day_type": "Day Type"},
            color="day_type",
            color_discrete_sequence=["#636EFA", "#EF553B"],  # Blue for Weekday, Red for Weekend
        )

        st.plotly_chart(fig_weekday_weekend, use_container_width=True)

    with col2:
        # ✅ Display Percentage Breakdown
        total_accidents = df_high_risk_days["accident_count"].sum()
        df_high_risk_days["percentage"] = round((df_high_risk_days["accident_count"] / total_accidents) * 100, 1)

        fig_pie_days = px.pie(
            df_high_risk_days,
            names="weekday",
            values="accident_count",
            title="Accident Distribution by Day of the Week",
            color="weekday",
            color_discrete_sequence=px.colors.qualitative.Pastel,
        )

        st.plotly_chart(fig_pie_days, use_container_width=True)

        

else:
    st.warning("No data available. Adjust filters and try again.")

# ✅ Fetch Accidents by Age Group Data
df_age_group = get_accidents_by_age_group(where_clause)

st.subheader("👶🧑‍🦳 Accidents by Age Group")

if not df_age_group.empty:
    col1, col2 = st.columns([3, 2])

    with col1:
        st.write("Analyzing accident distribution across different age groups.")

        # ✅ Display Bar Chart
        fig_age_group = px.bar(
            df_age_group,
            x="age_group",
            y="accident_count",
            title="Accidents by Age Group",
            labels={"accident_count": "Number of Accidents", "age_group": "Age Group"},
            color="age_group",
            color_discrete_sequence=px.colors.qualitative.Pastel  # Soft colors for clarity
        )

        st.plotly_chart(fig_age_group, use_container_width=True)

    with col2:
        # ✅ Display Percentage Breakdown
        total_accidents = df_age_group["accident_count"].sum()
        df_age_group["percentage"] = round((df_age_group["accident_count"] / total_accidents) * 100, 1)

        fig_pie_age = px.pie(
            df_age_group,
            names="age_group",
            values="accident_count",
            title="Accident Distribution by Age Group",
            color="age_group",
            color_discrete_sequence=px.colors.qualitative.Pastel,
        )

        st.plotly_chart(fig_pie_age, use_container_width=True)

else:
    st.warning("No data available. Adjust filters and try again.")


# ✅ Fetch Fatalities by Age Data
df_fatalities_age = get_fatalities_by_age(where_clause)

st.subheader("Fatalities by Age Group")

if not df_fatalities_age.empty:
    st.write("Table showing the distribution of fatal accidents across age groups.")

    # ✅ Remove the index before displaying
    df_fatalities_age = df_fatalities_age.reset_index(drop=True)

    # ✅ Display clean table without index
    st.table(df_fatalities_age.style.format({
        "fatality_count": "{:,}"
    }))
else:
    st.warning("No fatality data available. Adjust filters and try again.")

