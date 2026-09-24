FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src
COPY DBAPulse.sln .
COPY src ./src
RUN dotnet restore src/DBAPulse.Collector/DBAPulse.Collector.csproj
COPY queries ./queries
COPY database ./database
RUN dotnet publish src/DBAPulse.Collector/DBAPulse.Collector.csproj -c Release -o /out --no-restore

FROM mcr.microsoft.com/dotnet/runtime:8.0 AS runtime
WORKDIR /app
COPY --from=build /out .
ENTRYPOINT ["dotnet", "DBAPulse.Collector.dll"]
