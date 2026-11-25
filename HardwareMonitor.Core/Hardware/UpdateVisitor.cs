using LibreHardwareMonitor.Hardware;

namespace HardwareMonitor.Core.Hardware;

public sealed class UpdateVisitor : IVisitor
{
    public void VisitComputer(IComputer computer)
    {
        computer.Traverse(this);
    }

    public void VisitHardware(IHardware hardware)
    {
        // Match the working client, which updates each hardware node twice per sample.
        hardware.Update();
        hardware.Update();
        foreach (IHardware child in hardware.SubHardware)
            child.Accept(this);
    }

    public void VisitSensor(ISensor sensor)
    {
    }

    public void VisitParameter(IParameter parameter)
    {
    }
}
