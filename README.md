# Prema Prediction Market

A [prediction market](https://en.wikipedia.org/wiki/Prediction_market) web app.
Make predictions and trade on them with play money.
So far only provides binary markets.

![screenshot](https://raw.githubusercontent.com/qznc/prema/master/screenshot.png)

Prediction markets are also known as predictive markets, information markets, decision markets, idea futures, event derivatives, or virtual markets.

Uses [Mozilla Persona](http://127.0.0.1:8080) for authentification.

## Setup

SQLite is included, so you only need a D compiler
and the dub packaging tool.

1. Compile and run prema via `dub`.
2. Browse to `http://127.0.0.1:8080`.

## Desirable Features

* Multi-outcome markets
* Conditional and combinatorial markets
* Multiple languages (e.g. german)
* Limit and stop orders
* Shibboleth authentication
* REST API
* Real-time UI via Javascript magic

## Legalese

Unless otherwise marked (e.g. sqlite3), all code is provided under the
[Apache Licence v2.0](https://www.apache.org/licenses/LICENSE-2.0).

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
