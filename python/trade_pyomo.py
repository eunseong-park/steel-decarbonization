import pyomo.environ as pyo
from pyomo.mpec import Complementarity
import pandas as pd
import os

def solve_mcp(model):
    solver_name = 'pathampl'
    solver = pyo.SolverFactory(solver_name)
    if not solver.available():
        print(f"ERROR: Solver '{solver_name}' not available.")
        return False
    
    results = solver.solve(model, tee=True)
    return results.solver.termination_condition == pyo.TerminationCondition.optimal

def build_trade_model(transport_cost_scale=1.0):
    m = pyo.ConcreteModel(name="Trade_Model")

    # 1. Sets
    regions = ['A', 'B']
    m.R = pyo.Set(initialize=regions)

    # 2. Input Data
    # Quantities (Trade Flows)
    quantities_data = {
        ("A", "A"): 800,
        ("A", "B"): 200,
        ("B", "A"): 400,
        ("B", "B"): 1800
    }
    
    # Costs (Transport) - Base
    costs_data = {
        ("A", "A"): 100,
        ("A", "B"): 60,
        ("B", "A"): 90,
        ("B", "B"): 0
    }
    
    # Scenario Costs
    costs_data_scen = costs_data.copy()
    costs_data_scen[("B", "A")] *= transport_cost_scale
    
    # Reference Producer Price
    ref_P_data = {"A": 190, "B": 220}

    # Parameters
    epsilon = -1.0

    # 3. Calibration / Parameter Calculation
    
    # ref_YM[r, rr]
    ref_YM = quantities_data
    
    # tcost[r, rr] - Initialized with Scenario Data
    m.tcost = pyo.Param(m.R, m.R, initialize=costs_data_scen)
    
    # ref_P[r]
    ref_P = ref_P_data

    # ref_PM[r, rr] - Calculated with BASE Data
    ref_PM = {}
    for r in regions:
        for rr in regions:
            ref_PM[(r, rr)] = ref_P[r] + costs_data[(r, rr)]

    # ref_YA[r] = Sum(rr, ref_YM[rr, r]) (Total consumption in r)
    ref_YA = {}
    for r in regions:
        total = sum(ref_YM[(rr, r)] for rr in regions)
        ref_YA[r] = total

    # ref_CM[r] = Sum(rr, ref_YM[rr, r] * ref_PM[rr, r]) (Total import cost)
    ref_CM = {}
    for r in regions:
        val = sum(ref_YM[(rr, r)] * ref_PM[(rr, r)] for rr in regions)
        ref_CM[r] = val

    # ref_PA[r] = ref_CM[r] / ref_YA[r] (Weighted average price)
    ref_PA = {}
    for r in regions:
        ref_PA[r] = ref_CM[r] / ref_YA[r]

    # sha_PM[rr, r] = (ref_YM[rr, r] * ref_PM[rr, r]) / ref_CM[r] (Value share)
    sha_PM = {}
    for r in regions:
        for rr in regions: # rr is source, r is dest
            sha_PM[(rr, r)] = (ref_YM[(rr, r)] * ref_PM[(rr, r)]) / ref_CM[r]

    # Macro for Cost Function C_PM(r)
    def C_PM_expr(model, r):
        return sum(
            sha_PM[(rrr, r)] * (model.PM[rrr, r] / ref_PM[(rrr, r)])
            for rrr in model.R
        )

    # 4. Variables
    # YM: Trade quantity (r to rr)
    m.YM = pyo.Var(m.R, m.R, domain=pyo.NonNegativeReals, initialize=lambda m, r, rr: ref_YM[(r, rr)])
    
    # PM: Import price (r to rr)
    m.PM = pyo.Var(m.R, m.R, domain=pyo.NonNegativeReals, initialize=lambda m, r, rr: ref_PM[(r, rr)])
    
    # PA: Final price (r)
    m.PA = pyo.Var(m.R, domain=pyo.NonNegativeReals, initialize=lambda m, r: ref_PA[r])
    
    # YA: Final demand (r)
    m.YA = pyo.Var(m.R, domain=pyo.NonNegativeReals, initialize=lambda m, r: ref_YA[r])

    # 5. Complementarity Conditions

    # zpf_YM: Zero profit condition: import
    def zpf_YM_rule(model, r, rr):
        lhs = model.YM[r, rr]
        rhs = ref_YM[(r, rr)] * (1 + epsilon * (C_PM_expr(model, rr) - 1))
        return (lhs - rhs >= 0, model.YM[r, rr] >= 0)
    m.zpf_YM = Complementarity(m.R, m.R, rule=zpf_YM_rule)

    # mkt_PM: Market clearing: import
    def mkt_PM_rule(model, r, rr):
        lhs = ref_P[r] + model.tcost[r, rr]
        rhs = model.PM[r, rr]
        return (lhs - rhs >= 0, model.PM[r, rr] >= 0)
    m.mkt_PM = Complementarity(m.R, m.R, rule=mkt_PM_rule)

    # zpf_YA: Zero profit condition: final good
    def zpf_YA_rule(model, r):
        lhs = model.YA[r]
        rhs = ref_YA[r] * (1 + epsilon * (model.PA[r] / ref_PA[r] - 1))
        return (lhs - rhs >= 0, model.YA[r] >= 0)
    m.zpf_YA = Complementarity(m.R, rule=zpf_YA_rule)

    # mkt_PA: Market clearing condition: final good
    def mkt_PA_rule(model, r):
        lhs = ref_PA[r] * C_PM_expr(model, r)
        rhs = model.PA[r]
        return (lhs - rhs >= 0, model.PA[r] >= 0)
    m.mkt_PA = Complementarity(m.R, rule=mkt_PA_rule)
    
    return m

def collect_results(m, scenario_name):
    data = []
    for r in m.R:
        data.append({
            "Scenario": scenario_name,
            "Variable": "PA",
            "Region_From": r,
            "Region_To": None,
            "Value": pyo.value(m.PA[r])
        })
        data.append({
            "Scenario": scenario_name,
            "Variable": "YA",
            "Region_From": r,
            "Region_To": None,
            "Value": pyo.value(m.YA[r])
        })
        for rr in m.R:
            data.append({
                "Scenario": scenario_name,
                "Variable": "YM",
                "Region_From": r,
                "Region_To": rr,
                "Value": pyo.value(m.YM[r,rr])
            })
            data.append({
                "Scenario": scenario_name,
                "Variable": "PM",
                "Region_From": r,
                "Region_To": rr,
                "Value": pyo.value(m.PM[r,rr])
            })
    return data

def main():
    print("--- Initializing Trade Model (Pyomo) ---")
    all_results = []

    # 6. Solve 1: Benchmark
    print("\n--- Solving Benchmark Scenario ---")
    m_bench = build_trade_model(transport_cost_scale=1.0)
    success = solve_mcp(m_bench)
    
    if success:
        print("Benchmark Solved.")
        all_results.extend(collect_results(m_bench, "Benchmark"))
    else:
        print("Benchmark Failed.")

    # 7. Solve 2: Increased Transport Cost
    print("\n--- Solving Scenario: Double Transport Cost B->A ---")
    m_scen = build_trade_model(transport_cost_scale=2.0)
    success = solve_mcp(m_scen)
    
    if success:
        print("Scenario Solved.")
        all_results.extend(collect_results(m_scen, "Double_TC_BA"))
    else:
        print("Scenario Failed.")

    # 8. Export Results
    if all_results:
        output_dir = "output/python"
        if not os.path.exists(output_dir):
            os.makedirs(output_dir)
        
        df = pd.DataFrame(all_results)
        print("\nResults Summary:")
        print(df.head())
        
        out_path = os.path.join(output_dir, "trade_results_pyomo.csv")
        df.to_csv(out_path, index=False)
        print(f"\nSaved results to {out_path}")

if __name__ == "__main__":
    main()
